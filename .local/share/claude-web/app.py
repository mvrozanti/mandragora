"""
claude.mvr.ac — add a tmux window running `claude` to the user's
current session and return a ✓. Picks the most-recently-active
attached session; falls back to any existing session; only spawns
a new session if tmux is empty.
"""
import asyncio
import json
import os
from pathlib import Path

import aiohttp
from aiohttp import web

HOME = Path(os.environ.get("HOME", "/home/m")).resolve()
LISTEN_HOST = os.environ.get("CLAUDE_WEB_HOST", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("CLAUDE_WEB_PORT", "7682"))
XDG_RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR", "/run/user/1000")
FALLBACK_SESSION = os.environ.get("CLAUDE_WEB_FALLBACK_SESSION", "claude")
EXCLUDE = {".git", "node_modules", "__pycache__", ".venv", ".direnv", ".cache", ".tmp"}
DEVTOOLS_UPSTREAM = os.environ.get("CLAUDE_DEVTOOLS_UPSTREAM", "http://127.0.0.1:3456")
_HOP_HEADERS = {
    "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
    "te", "trailers", "transfer-encoding", "upgrade", "content-length",
    "content-encoding", "host",
}


def resolve_dir(raw: str | None) -> Path:
    if raw is None or raw == "":
        return HOME
    raw = raw.strip()
    if raw == "~":
        return HOME
    if raw.startswith("~/"):
        return (HOME / raw[2:]).resolve()
    return Path(raw).expanduser().resolve()


async def tmux(*args: str, env: dict) -> tuple[int, str, str]:
    proc = await asyncio.create_subprocess_exec(
        "tmux", *args, env=env,
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
    )
    out, err = await proc.communicate()
    return proc.returncode, out.decode(errors="replace"), err.decode(errors="replace")


async def pick_session(env: dict) -> str | None:
    rc, out, _ = await tmux(
        "list-clients", "-F", "#{client_activity} #{session_name}", env=env,
    )
    if rc == 0 and out.strip():
        lines = [l for l in out.splitlines() if l.strip()]
        lines.sort(key=lambda l: int(l.split(" ", 1)[0]), reverse=True)
        return lines[0].split(" ", 1)[1]
    rc, out, _ = await tmux(
        "list-sessions", "-F", "#{session_activity} #{session_name}", env=env,
    )
    if rc == 0 and out.strip():
        lines = [l for l in out.splitlines() if l.strip()]
        lines.sort(key=lambda l: int(l.split(" ", 1)[0]), reverse=True)
        return lines[0].split(" ", 1)[1]
    return None


async def tmux_spawn(target: Path) -> tuple[bool, str, str]:
    env = {**os.environ, "XDG_RUNTIME_DIR": XDG_RUNTIME_DIR, "HOME": str(HOME)}
    session = await pick_session(env)
    name = target.name or target.anchor.strip("/") or "claude"

    if session is not None:
        rc, out, err = await tmux(
            "new-window", "-t", f"{session}:", "-c", str(target),
            "-n", name, "-P", "-F", "#{window_index}", "claude", env=env,
        )
        action = "added window"
    else:
        session = FALLBACK_SESSION
        rc, out, err = await tmux(
            "new-session", "-d", "-s", session, "-c", str(target),
            "-n", name, "-P", "-F", "#{window_index}", "claude", env=env,
        )
        action = "spawned session"

    if rc != 0:
        return False, session, err.strip()[:500] or "tmux failed"
    window = out.strip().splitlines()[-1] if out.strip() else "?"
    await tmux(
        "set-option", "-w", "-t", f"{session}:{window}",
        "@claude_dir", str(target), env=env,
    )
    return True, f"{session}:{window}", action


async def api_list(req: web.Request) -> web.Response:
    raw = req.query.get("path", "")
    p = resolve_dir(raw)
    if not p.is_dir():
        return web.json_response({"ok": False, "error": f"not a directory: {p}"}, status=400)
    try:
        entries = []
        for e in sorted(p.iterdir(), key=lambda x: x.name.lower()):
            if e.name in EXCLUDE or e.name.startswith(".cache"):
                continue
            try:
                if not e.is_dir():
                    continue
            except OSError:
                continue
            entries.append({"name": e.name})
        parent = str(p.parent) if p != p.parent else None
        return web.json_response({"ok": True, "path": str(p), "parent": parent, "entries": entries})
    except PermissionError as exc:
        return web.json_response({"ok": False, "error": str(exc)}, status=403)


async def api_zoxide(req: web.Request) -> web.Response:
    q = req.query.get("q", "").strip()
    args = ["zoxide", "query", "-ls"]
    if q:
        args += q.split()
    proc = await asyncio.create_subprocess_exec(
        *args, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
    )
    out, _ = await proc.communicate()
    entries = []
    for line in out.decode(errors="replace").splitlines():
        line = line.strip()
        if not line:
            continue
        score_str, _, path_str = line.partition(" ")
        path_str = path_str.strip()
        if not path_str:
            continue
        try:
            score = float(score_str)
        except ValueError:
            continue
        try:
            p = Path(path_str)
            if not p.is_dir():
                continue
        except OSError:
            continue
        entries.append({"score": score, "path": str(p)})
    return web.json_response({"ok": True, "entries": entries[:30]})


async def api_launch(req: web.Request) -> web.Response:
    body = await req.json()
    target = resolve_dir(body.get("dir"))
    if not target.is_dir():
        return web.json_response({"ok": False, "error": f"not a directory: {target}"}, status=400)
    ok, session, msg = await tmux_spawn(target)
    status = 200 if ok else 500
    return web.json_response({"ok": ok, "session": session, "dir": str(target), "msg": msg}, status=status)


async def _proxy_devtools(req: web.Request, upstream_path: str) -> web.StreamResponse:
    session: aiohttp.ClientSession = req.app["dt_client"]
    url = DEVTOOLS_UPSTREAM + upstream_path
    if req.query_string:
        url += "?" + req.query_string
    fwd = {k: v for k, v in req.headers.items() if k.lower() not in _HOP_HEADERS}
    body = await req.read() if req.body_exists else None
    try:
        up = await session.request(req.method, url, headers=fwd, data=body, allow_redirects=False)
    except aiohttp.ClientError as exc:
        return web.Response(status=502, text=f"claude-devtools upstream unreachable: {exc}")
    resp = web.StreamResponse(status=up.status)
    for k, v in up.headers.items():
        if k.lower() not in _HOP_HEADERS:
            resp.headers[k] = v
    await resp.prepare(req)
    try:
        async for chunk in up.content.iter_any():
            await resp.write(chunk)
    except (ConnectionResetError, asyncio.CancelledError):
        pass
    finally:
        up.release()
    try:
        await resp.write_eof()
    except (ConnectionResetError, asyncio.CancelledError):
        pass
    return resp


async def dt_app(req: web.Request) -> web.StreamResponse:
    return await _proxy_devtools(req, "/" + req.match_info.get("tail", ""))


async def dt_api(req: web.Request) -> web.StreamResponse:
    return await _proxy_devtools(req, "/api/" + req.match_info.get("tail", ""))


INDEX_HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover,interactive-widget=resizes-content">
<title>claude.mvr.ac</title>
<style>
  :root {
    color-scheme: dark;
    --bg: #050805;
    --panel: #0a0e0a;
    --fg: #b8ffc4;
    --accent: #00ff66;
    --dim: #4a6a4e;
    --hover: #0f1810;
    --line: #1a2418;
    --warn: #ffb347;
    --err: #ff6b6b;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  html, body {
    background: var(--bg); color: var(--fg);
    font-family: "Iosevka", "JetBrains Mono", "Fira Code", ui-monospace, monospace;
    min-height: 100dvh;
    -webkit-tap-highlight-color: transparent;
  }
  body { padding: 2.5rem 2rem; position: relative; overflow-x: hidden; font-size: 16px; line-height: 1.5; }
  body::before {
    content: ''; position: fixed; inset: 0; pointer-events: none;
    background: radial-gradient(circle at 30% 20%, rgba(0,255,102,0.04), transparent 50%);
    z-index: 0;
  }
  .wrap { position: relative; z-index: 1; max-width: 720px; margin: 0 auto; }
  header {
    display: flex; justify-content: space-between; align-items: baseline;
    border-bottom: 1px solid var(--line); padding-bottom: 1rem; margin-bottom: 2rem;
  }
  header h1 { font-size: 1.05rem; font-weight: normal; color: var(--fg); letter-spacing: 0.02em; }
  header h1::before { content: '$ '; color: var(--accent); }
  header h1 .cursor { color: var(--accent); animation: blink 1.1s infinite; }
  @keyframes blink { 0%, 50% { opacity: 1; } 50.01%, 100% { opacity: 0; } }
  header .nav { color: var(--dim); font-size: 0.78rem; }
  header .nav a { color: var(--accent); text-decoration: none; margin-left: 0.75rem; }
  header .nav a:hover { text-decoration: underline; }

  .card { background: var(--panel); border: 1px solid var(--line); padding: 1.5rem; }

  .crumb { color: var(--dim); margin-bottom: 1.25rem; font-size: 0.85rem; word-break: break-all; line-height: 1.7; }
  .crumb a { color: var(--accent); text-decoration: none; }
  .crumb a:hover { text-decoration: underline; }
  .crumb .sep { color: var(--line); padding: 0 0.3rem; }

  .open-here {
    width: 100%; padding: 0.9rem 1rem; border: 1px solid var(--accent); background: var(--hover);
    color: var(--fg); font: inherit; cursor: pointer; margin-bottom: 1rem;
    transition: background 0.12s, box-shadow 0.12s; text-align: left;
    display: flex; align-items: center; gap: 0.75rem;
  }
  .open-here:hover { background: var(--panel); box-shadow: 0 0 12px rgba(0,255,102,0.25); }
  .open-here:active { transform: translateY(1px); }
  .open-here b { color: var(--accent); font-weight: 500; }
  .open-here .shortcut { margin-left: auto; color: var(--dim); }

  .filter {
    width: 100%; padding: 0.65rem 0.8rem; background: var(--bg); border: 1px solid var(--line);
    color: var(--fg); font: inherit; margin-bottom: 0.6rem;
  }
  .filter:focus { outline: none; border-color: var(--accent); }

  .list { display: flex; flex-direction: column; gap: 2px; max-height: 60dvh; overflow-y: auto; padding-right: 4px; scroll-padding: 0.3rem; }
  .list::-webkit-scrollbar { width: 6px; }
  .list::-webkit-scrollbar-thumb { background: var(--line); }
  .row {
    display: flex; align-items: center; gap: 0.7rem; padding: 0.55rem 0.75rem;
    cursor: pointer; color: var(--fg); text-decoration: none;
    border: 1px solid transparent;
  }
  .row:hover { background: var(--hover); border-color: var(--line); }
  .row.sel { background: var(--hover); border-color: var(--accent); }
  .row.sel .ico, .row.sel .arrow { color: var(--accent); }
  .row.up { color: var(--dim); }
  .row.zox .ico { color: var(--warn); font-weight: bold; }
  .row.zox .arrow { color: var(--warn); font-variant-numeric: tabular-nums; font-size: 0.78rem; }
  .row .ico { color: var(--accent); font-size: 1.05em; flex-shrink: 0; opacity: 0.8; }
  .row.up .ico { color: var(--dim); }
  .row .name { flex: 1; word-break: break-all; }
  .row .arrow { color: var(--dim); }

  .hints {
    display: flex; flex-wrap: wrap; gap: 0.35rem 0.9rem; margin-top: 1rem;
    padding-top: 0.9rem; border-top: 1px solid var(--line);
    color: var(--dim); font-size: 0.72rem; letter-spacing: 0.05em;
  }
  .hints span { display: inline-flex; align-items: center; gap: 0.35rem; }
  kbd {
    display: inline-block; min-width: 1.2em; text-align: center;
    padding: 0.04rem 0.35rem; background: var(--bg); color: var(--fg);
    border: 1px solid var(--line); border-radius: 2px;
    font-size: 0.85em; font-family: inherit; line-height: 1.25;
  }

  .empty { color: var(--dim); text-align: center; padding: 1.5rem; font-style: italic; }
  .err {
    background: rgba(255,107,107,0.08); border: 1px solid var(--err);
    color: var(--err); padding: 0.9rem 1rem; margin-top: 1rem;
  }

  .ok-wrap { display: flex; flex-direction: column; align-items: center; gap: 1.25rem; padding: 1.75rem 0 0.5rem; }
  .check {
    width: 96px; height: 96px; border: 1px solid var(--accent);
    background: var(--panel);
    box-shadow: 0 0 24px -4px rgba(0,255,102,0.4), inset 0 0 16px rgba(0,255,102,0.08);
    display: grid; place-items: center; color: var(--accent);
    animation: pop 0.35s cubic-bezier(0.18,0.89,0.32,1.28);
  }
  .check.pending { border-color: var(--dim); color: var(--dim); box-shadow: none; animation: spin 1.2s linear infinite; }
  @keyframes pop { from { transform: scale(0.2); opacity: 0; } to { transform: scale(1); opacity: 1; } }
  @keyframes spin { to { transform: rotate(360deg); } }

  .ok-wrap h2 { font-size: 1.05rem; font-weight: 500; letter-spacing: 0.02em; color: var(--fg); }
  .ok-wrap p { color: var(--fg); font-size: 0.85rem; text-align: center; word-break: break-all; }
  .ok-wrap code { color: var(--accent); background: var(--bg); padding: 0.18rem 0.5rem; border: 1px solid var(--line); font-size: 0.82rem; }
  .ok-wrap .hint { color: var(--dim); font-size: 0.78rem; }
  .back { color: var(--accent); text-decoration: none; font-size: 0.85rem; }
  .back:hover { text-decoration: underline; }

  footer {
    margin-top: 2.5rem; padding-top: 1rem; border-top: 1px solid var(--line);
    display: flex; justify-content: space-between; align-items: baseline;
    color: var(--dim); font-size: 0.72rem;
  }
  footer a { color: var(--accent); text-decoration: none; }
  footer a:hover { text-decoration: underline; }

  .row, .open-here, .filter { transition: background 60ms ease; }
  .row:active { background: var(--hover); }
  .open-here:active { background: var(--panel); }

  @media (hover: none) and (pointer: coarse) {
    .row {
      padding: 0.85rem 0.9rem;
      min-height: 48px;
      gap: 0.85rem;
    }
    .row .ico { font-size: 1.15em; width: 1.35em; text-align: center; }
    .filter {
      padding: 0.7rem 0.9rem;
      font-size: 16px;
      min-height: 44px;
    }
    .crumb a {
      display: inline-block;
      padding: 0.2rem 0.35rem;
      min-height: 28px;
    }
    .crumb .sep { padding: 0 0.15rem; }
    header .nav a { padding: 0.3rem 0.5rem; display: inline-block; }
    .hints { display: none; }
  }

  @media (max-width: 600px) {
    html, body {
      height: 100vh;
      height: 100dvh;
      overflow: hidden;
    }
    body {
      padding: 0.5rem 0.6rem;
      padding-top: max(0.5rem, env(safe-area-inset-top));
      padding-bottom: max(0.5rem, env(safe-area-inset-bottom));
      padding-left: max(0.6rem, env(safe-area-inset-left));
      padding-right: max(0.6rem, env(safe-area-inset-right));
      font-size: 15px;
    }
    .wrap {
      display: flex;
      flex-direction: column;
      height: 100%;
      max-width: none;
    }
    header {
      padding-bottom: 0.5rem;
      margin-bottom: 0.55rem;
      flex-shrink: 0;
    }
    header h1 { font-size: 0.95rem; }
    header .nav { font-size: 0.78rem; }
    header .nav a { margin-left: 0.5rem; }
    .card {
      padding: 0.7rem;
      padding-bottom: max(0.7rem, env(keyboard-inset-height, 0px));
      flex: 1 1 auto;
      min-height: 0;
      display: flex;
      flex-direction: column;
    }
    .crumb {
      margin-bottom: 0.55rem;
      font-size: 0.85rem;
      line-height: 1.6;
      flex-shrink: 0;
    }
    .open-here {
      padding: 0.6rem 0.8rem;
      min-height: 44px;
      font-size: 0.9rem;
      margin-bottom: 0.5rem;
      flex-shrink: 0;
    }
    .open-here .shortcut { display: none; }
    .filter {
      margin-bottom: 0.4rem;
      flex-shrink: 0;
    }
    .list {
      max-height: none;
      flex: 1 1 auto;
      min-height: 0;
      padding-right: 2px;
    }
    footer { display: none; }
    .ok-wrap { padding: 1rem 0 0.5rem; gap: 1rem; }
    .check { width: 80px; height: 80px; }
  }

  .tabs { display: flex; gap: 0.5rem; margin-bottom: 1.25rem; }
  .tab {
    background: var(--panel); border: 1px solid var(--line); color: var(--dim);
    font: inherit; font-size: 0.82rem; padding: 0.4rem 1.1rem; cursor: pointer;
    transition: background 0.12s, color 0.12s, border-color 0.12s; letter-spacing: 0.03em;
  }
  .tab:hover { color: var(--fg); }
  .tab.active { color: var(--accent); border-color: var(--accent); background: var(--hover); }
  #dt-pane { height: 82dvh; border: 1px solid var(--line); background: var(--bg); }
  #dt-frame { width: 100%; height: 100%; border: 0; display: block; }
  .wrap.dt-active { max-width: 1400px; transition: max-width 0.2s ease; }

  @media (max-width: 600px) {
    .wrap.dt-active { max-width: none; }
    .tabs { margin-bottom: 0.5rem; flex-shrink: 0; }
    #spawn-pane { flex: 1 1 auto; min-height: 0; display: flex; flex-direction: column; }
    #dt-pane { flex: 1 1 auto; min-height: 0; height: auto; border: 0; }
  }
</style>
</head>
<body>
<div class="wrap">
  <header>
    <h1>claude<span class="cursor">_</span></h1>
    <div class="nav">
      <a href="https://hub.mvr.ac/">hub</a>
      <a href="https://auth.mvr.ac/logout">logout</a>
    </div>
  </header>
  <nav class="tabs">
    <button type="button" class="tab active" data-tab="spawn">spawn</button>
    <button type="button" class="tab" data-tab="devtools">devtools</button>
  </nav>
  <div id="spawn-pane">
    <div class="card" id="root"></div>
    <footer>
      <span>mvr.ac · claude</span>
      <span><a href="https://hub.mvr.ac">hub</a> · <a href="https://mvr.ac">root</a></span>
    </footer>
  </div>
  <div id="dt-pane" hidden>
    <iframe id="dt-frame" title="claude-devtools" referrerpolicy="no-referrer"></iframe>
  </div>
</div>
<script>
if ('virtualKeyboard' in navigator) navigator.virtualKeyboard.overlaysContent = true;
const root = document.getElementById('root');
const params = new URLSearchParams(location.search);
const dirParam = params.get('dir');
const HOME = __HOME_JSON__;

const $ = (s) => document.createElement(s);
const esc = (s) => String(s).replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));

function checkSvg() {
  return `<svg width="56" height="56" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><polyline points="5 12 10 17 19 8"/></svg>`;
}
function spinSvg() {
  return `<svg width="44" height="44" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><path d="M21 12a9 9 0 1 1-6.2-8.55" /></svg>`;
}

function renderOk(j) {
  root.innerHTML = `
<div class="ok-wrap">
      <div class="check">${checkSvg()}</div>
      <h2>claude ready</h2>
      <p><code>${esc(j.session)}</code></p>
      <p>${esc(j.dir)}</p>
      <p class="hint">${esc(j.msg)} — attach via your tmux client</p>
      <a class="back" href="/">← spawn another</a>
    </div>
  `;
}

function renderSpawning(dir) {
  root.innerHTML = `
<div class="ok-wrap">
      <div class="check pending">${spinSvg()}</div>
      <h2>spawning…</h2>
      <p>${esc(dir)}</p>
    </div>
  `;
}

function renderError(msg) {
  root.innerHTML = `
<div class="err">${esc(msg)}</div>
    <p style="text-align:center;margin-top:1rem"><a class="back" href="/">← try again</a></p>
  `;
}

async function spawn(dir) {
  renderSpawning(dir);
  try {
    const r = await fetch('/api/launch', {
      method: 'POST',
      headers: {'content-type': 'application/json'},
      body: JSON.stringify({dir}),
    });
    const j = await r.json();
    if (j.ok) renderOk(j);
    else renderError(j.error || 'launch failed');
  } catch (e) {
    renderError(String(e));
  }
}

function crumbHtml(path) {
  const homeIsPrefix = path === HOME || path.startsWith(HOME + '/');
  const segments = [];
  let acc = '';
  let display = path;
  if (homeIsPrefix) {
    segments.push({ label: '~', href: HOME });
    const rest = path.slice(HOME.length);
    rest.split('/').filter(Boolean).forEach(seg => {
      acc = (acc || HOME) + '/' + seg;
      segments.push({ label: seg, href: acc });
    });
  } else {
    segments.push({ label: '/', href: '/' });
    path.split('/').filter(Boolean).forEach(seg => {
      acc += '/' + seg;
      segments.push({ label: seg, href: acc });
    });
  }
  return segments.map((s, i) =>
    `<a href="#${encodeURIComponent(s.href)}">${esc(s.label)}</a>` +
    (i < segments.length - 1 ? '<span class="sep">/</span>' : '')
  ).join('');
}

const selectionMemory = {};

async function renderPicker(path) {
  const r = await fetch('/api/list?path=' + encodeURIComponent(path));
  const j = await r.json();
  if (!j.ok) { renderError(j.error || 'list failed'); return; }

  const subdirRows = [];
  if (j.parent) subdirRows.push({ kind: 'up', name: '..', href: j.parent });
  for (const e of j.entries) {
    const sub = (j.path.endsWith('/') ? j.path : j.path + '/') + e.name;
    subdirRows.push({ kind: 'dir', name: e.name, href: sub });
  }

  root.innerHTML = `
<div class="crumb">${crumbHtml(j.path)}</div>
    <button class="open-here" id="openHere">
      <span style="color:#9ece6a">▸</span>
      <span>open <b>this</b> directory in claude</span>
      <span class="shortcut"><kbd>Ctrl</kbd>+<kbd>↵</kbd></span>
    </button>
    <input class="filter" id="filter" placeholder="filter or fuzzy-jump via zoxide…" autocomplete="off" spellcheck="false">
    <div class="list" id="list"></div>
    <div class="hints">
      <span><kbd>↑</kbd><kbd>↓</kbd> move</span>
      <span><kbd>↵</kbd> enter dir</span>
      <span><kbd>Ctrl</kbd>+<kbd>↵</kbd> open here</span>
      <span><kbd>⌫</kbd> parent</span>
      <span><kbd>Esc</kbd> clear</span>
    </div>
  `;

  document.getElementById('openHere').onclick = () => spawn(j.path);
  const filter = document.getElementById('filter');
  const list = document.getElementById('list');

  let zoxideRows = [];
  let visible = [];
  let sel = 0;
  let zoxideToken = 0;

  function shortHome(p) {
    if (p === HOME) return '~';
    if (p.startsWith(HOME + '/')) return '~' + p.slice(HOME.length);
    return p;
  }

  function rowHtml(row, i) {
    if (row.kind === 'up') {
      return `<a class="row up" data-idx="${i}" href="#${encodeURIComponent(row.href)}"><span class="ico">↑</span><span class="name">..</span></a>`;
    }
    if (row.kind === 'zoxide') {
      return `<a class="row zox" data-idx="${i}" href="#${encodeURIComponent(row.href)}"><span class="ico">z</span><span class="name">${esc(row.label)}</span><span class="arrow">${row.score.toFixed(1)}</span></a>`;
    }
    return `<a class="row" data-idx="${i}" href="#${encodeURIComponent(row.href)}"><span class="ico">▸</span><span class="name">${esc(row.name)}</span><span class="arrow">→</span></a>`;
  }

  function renderList() {
    list.innerHTML = visible.length
      ? visible.map(rowHtml).join('')
      : '<div class="empty">(no matches)</div>';
  }

  function applyFilter() {
    const q = filter.value.toLowerCase();
    const subs = subdirRows.filter(r => r.kind === 'up' || !q || r.name.toLowerCase().includes(q));
    visible = q ? [...zoxideRows, ...subs] : subs;
    if (sel >= visible.length) sel = Math.max(0, visible.length - 1);
    renderList();
    paintSel();
  }

  async function fetchZoxide(q) {
    const my = ++zoxideToken;
    if (!q) {
      zoxideRows = [];
      applyFilter();
      return;
    }
    try {
      const r = await fetch('/api/zoxide?q=' + encodeURIComponent(q));
      const j2 = await r.json();
      if (my !== zoxideToken) return;
      zoxideRows = (j2.entries || []).map(e => ({
        kind: 'zoxide', href: e.path, label: shortHome(e.path), score: e.score,
      }));
      applyFilter();
    } catch (_) {
      if (my === zoxideToken) { zoxideRows = []; applyFilter(); }
    }
  }

  function paintSel() {
    list.querySelectorAll('.row.sel').forEach(el => el.classList.remove('sel'));
    const row = visible[sel];
    if (!row) return;
    const el = list.querySelector('.row[data-idx="' + sel + '"]');
    if (el) {
      el.classList.add('sel');
      el.scrollIntoView({ block: 'nearest' });
    }
  }

  function activate(row) {
    if (!row) return;
    if (row.kind === 'up') {
      const here = j.path.split('/').filter(Boolean).pop() || '';
      if (here) selectionMemory[row.href] = here;
    }
    location.hash = encodeURIComponent(row.href);
  }

  let zoxideTimer = null;
  filter.addEventListener('input', () => {
    sel = 0;
    applyFilter();
    clearTimeout(zoxideTimer);
    const q = filter.value;
    zoxideTimer = setTimeout(() => fetchZoxide(q), 80);
  });

  filter.addEventListener('keydown', (e) => {
    const empty = filter.value === '';
    const atEnd = filter.selectionStart === filter.value.length;
    const k = e.key;
    if (k === 'ArrowDown' || (e.ctrlKey && (k === 'n' || k === 'j'))) {
      e.preventDefault();
      if (sel < visible.length - 1) { sel++; paintSel(); }
    } else if (k === 'ArrowUp' || (e.ctrlKey && (k === 'p' || k === 'k'))) {
      e.preventDefault();
      if (sel > 0) { sel--; paintSel(); }
    } else if (k === 'Enter') {
      e.preventDefault();
      if (e.ctrlKey || e.altKey || e.metaKey) {
        const row = visible[sel];
        spawn(row && row.kind === 'zoxide' ? row.href : j.path);
      } else activate(visible[sel]);
    } else if (k === 'Tab' && !e.shiftKey) {
      e.preventDefault();
      activate(visible[sel]);
    } else if (k === 'ArrowRight' && atEnd) {
      e.preventDefault();
      activate(visible[sel]);
    } else if ((k === 'Backspace' && empty) || (k === 'ArrowLeft' && empty)) {
      if (j.parent) {
        e.preventDefault();
        const here = j.path.split('/').filter(Boolean).pop() || '';
        if (here) selectionMemory[j.parent] = here;
        location.hash = encodeURIComponent(j.parent);
      }
    } else if (k === 'Escape') {
      if (filter.value) {
        e.preventDefault();
        filter.value = '';
        sel = 0;
        applyFilter();
      }
    } else if (k === 'Home' && empty) {
      e.preventDefault();
      sel = 0;
      paintSel();
    } else if (k === 'End' && empty) {
      e.preventDefault();
      sel = visible.length - 1;
      paintSel();
    } else if (k === 'PageDown' && empty) {
      e.preventDefault();
      sel = Math.min(visible.length - 1, sel + 8);
      paintSel();
    } else if (k === 'PageUp' && empty) {
      e.preventDefault();
      sel = Math.max(0, sel - 8);
      paintSel();
    }
  });

  list.addEventListener('mousemove', (e) => {
    const el = e.target.closest('.row');
    if (!el) return;
    const idx = +el.dataset.idx;
    if (idx >= 0 && idx !== sel) { sel = idx; paintSel(); }
  });

  applyFilter();

  const remembered = selectionMemory[j.path];
  if (remembered) {
    const idx = visible.findIndex(r => r.kind === 'dir' && r.name === remembered);
    if (idx >= 0) sel = idx;
  } else if (visible[0] && visible[0].kind === 'up' && visible.length > 1) {
    sel = 1;
  }
  paintSel();
  filter.focus();
}

function navigate() {
  const hash = decodeURIComponent(location.hash.slice(1)) || HOME;
  renderPicker(hash).catch(e => renderError(String(e)));
}

if (dirParam !== null) {
  spawn(dirParam || HOME);
} else {
  window.addEventListener('hashchange', navigate);
  navigate();
}

const tabBtns = document.querySelectorAll('.tab');
const spawnPane = document.getElementById('spawn-pane');
const dtPane = document.getElementById('dt-pane');
const dtFrame = document.getElementById('dt-frame');
const wrapEl = document.querySelector('.wrap');
function showTab(name) {
  const dt = name === 'devtools';
  if (dt && !dtFrame.src) dtFrame.src = '/devtools/';
  spawnPane.hidden = dt;
  dtPane.hidden = !dt;
  wrapEl.classList.toggle('dt-active', dt);
  tabBtns.forEach(b => b.classList.toggle('active', b.dataset.tab === name));
}
tabBtns.forEach(b => b.addEventListener('click', () => showTab(b.dataset.tab)));
</script>
</body>
</html>
"""


async def index(req: web.Request) -> web.Response:
    html = INDEX_HTML.replace("__HOME_JSON__", json.dumps(str(HOME)))
    return web.Response(text=html, content_type="text/html")


async def _open_dt_client(app: web.Application) -> None:
    app["dt_client"] = aiohttp.ClientSession(
        timeout=aiohttp.ClientTimeout(total=None, sock_read=None),
    )


async def _close_dt_client(app: web.Application) -> None:
    await app["dt_client"].close()


def main() -> None:
    app = web.Application()
    app.on_startup.append(_open_dt_client)
    app.on_cleanup.append(_close_dt_client)
    app.router.add_get("/", index)
    app.router.add_get("/api/list", api_list)
    app.router.add_get("/api/zoxide", api_zoxide)
    app.router.add_post("/api/launch", api_launch)
    app.router.add_route("*", "/devtools", dt_app)
    app.router.add_route("*", "/devtools/{tail:.*}", dt_app)
    app.router.add_route("*", "/api/{tail:.*}", dt_api)
    web.run_app(app, host=LISTEN_HOST, port=LISTEN_PORT, access_log=None, print=lambda *_: None)


if __name__ == "__main__":
    main()
