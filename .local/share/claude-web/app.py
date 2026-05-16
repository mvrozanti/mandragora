"""
claude.mvr.ac — spawn a detached tmux session running `claude` in a
chosen directory and return a ✓. No interactive terminal is served;
the user attaches via their own Claude client.
"""
import asyncio
import hashlib
import json
import os
from pathlib import Path

from aiohttp import web

HOME = Path(os.environ.get("HOME", "/home/m")).resolve()
LISTEN_HOST = os.environ.get("CLAUDE_WEB_HOST", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("CLAUDE_WEB_PORT", "7682"))
XDG_RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR", "/run/user/1000")
EXCLUDE = {".git", "node_modules", "__pycache__", ".venv", ".direnv", ".cache", ".tmp"}


def slug(p: str) -> str:
    return "claude-" + hashlib.sha1(p.encode()).hexdigest()[:10]


def resolve_dir(raw: str | None) -> Path:
    if raw is None or raw == "":
        return HOME
    raw = raw.strip()
    if raw == "~":
        return HOME
    if raw.startswith("~/"):
        return (HOME / raw[2:]).resolve()
    return Path(raw).expanduser().resolve()


async def tmux_spawn(target: Path) -> tuple[bool, str, str]:
    session = slug(str(target))
    env = {**os.environ, "XDG_RUNTIME_DIR": XDG_RUNTIME_DIR, "HOME": str(HOME)}
    has = await asyncio.create_subprocess_exec(
        "tmux", "has-session", "-t", f"={session}",
        env=env, stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL,
    )
    await has.wait()
    if has.returncode == 0:
        return True, session, "already running"
    proc = await asyncio.create_subprocess_exec(
        "tmux", "new-session", "-d", "-s", session, "-c", str(target), "claude",
        env=env, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
    )
    _, err = await proc.communicate()
    if proc.returncode != 0:
        return False, session, err.decode(errors="replace").strip()[:500] or "tmux failed"
    return True, session, "spawned"


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


async def api_launch(req: web.Request) -> web.Response:
    body = await req.json()
    target = resolve_dir(body.get("dir"))
    if not target.is_dir():
        return web.json_response({"ok": False, "error": f"not a directory: {target}"}, status=400)
    ok, session, msg = await tmux_spawn(target)
    status = 200 if ok else 500
    return web.json_response({"ok": ok, "session": session, "dir": str(target), "msg": msg}, status=status)


INDEX_HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>claude.mvr.ac</title>
<style>
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  body {
    margin: 0; min-height: 100vh;
    font: 14px/1.5 ui-monospace, "JetBrainsMono Nerd Font", "JetBrains Mono", "Fira Code", Menlo, monospace;
    background: radial-gradient(at 30% 0%, #1f2335 0%, #15161e 70%);
    color: #c0caf5;
    display: grid; place-items: center; padding: 2rem;
  }
  .card {
    background: #1a1b26; border: 1px solid #2a2f44; border-radius: 14px;
    padding: 1.75rem; width: 100%; max-width: 720px;
    box-shadow: 0 14px 40px -16px rgba(0,0,0,.7), 0 0 0 1px rgba(255,255,255,.02) inset;
  }
  .title { font-size: .8rem; letter-spacing: .14em; text-transform: uppercase; color: #565f89; margin-bottom: 1rem; }
  .title b { color: #7aa2f7; font-weight: 600; letter-spacing: .14em; }

  .crumb { color: #565f89; margin-bottom: 1.25rem; font-size: .92rem; word-break: break-all; line-height: 1.7; }
  .crumb a { color: #7aa2f7; text-decoration: none; }
  .crumb a:hover { color: #7dcfff; text-decoration: underline; }
  .crumb .sep { color: #3b4261; padding: 0 .3rem; }

  .open-here {
    width: 100%; padding: .95rem 1rem; border: 1px solid #7aa2f7; background: linear-gradient(180deg, #2a3047, #232842);
    color: #c0caf5; border-radius: 9px; font: inherit; cursor: pointer; margin-bottom: 1rem;
    transition: background .14s, transform .06s; text-align: left;
    display: flex; align-items: center; gap: .75rem;
  }
  .open-here:hover { background: linear-gradient(180deg, #303656, #262c4a); }
  .open-here:active { transform: translateY(1px); }
  .open-here b { color: #9ece6a; }

  .filter { width: 100%; padding: .65rem .8rem; background: #15161e; border: 1px solid #2a2f44; color: #c0caf5; border-radius: 8px; font: inherit; margin-bottom: .6rem; }
  .filter:focus { outline: none; border-color: #7aa2f7; }

  .list { display: flex; flex-direction: column; gap: 2px; max-height: 55vh; overflow-y: auto; padding-right: 4px; }
  .list::-webkit-scrollbar { width: 6px; }
  .list::-webkit-scrollbar-thumb { background: #2a2f44; border-radius: 3px; }
  .row {
    display: flex; align-items: center; gap: .7rem; padding: .55rem .75rem;
    border-radius: 7px; cursor: pointer; color: #c0caf5; text-decoration: none;
    border: 1px solid transparent;
  }
  .row:hover { background: #20222e; border-color: #2a2f44; }
  .row.up { color: #565f89; }
  .row .ico { color: #7aa2f7; font-size: 1.05em; flex-shrink: 0; }
  .row.up .ico { color: #565f89; }
  .row .name { flex: 1; word-break: break-all; }
  .row .arrow { color: #565f89; }

  .empty { color: #565f89; text-align: center; padding: 1.5rem; font-style: italic; }
  .err { background: #f7768e15; border: 1px solid #f7768e55; color: #f7768e; padding: .9rem 1rem; border-radius: 8px; margin-top: 1rem; }

  .ok-wrap { display: flex; flex-direction: column; align-items: center; gap: 1.25rem; padding: 1.75rem 0 .5rem; }
  .check {
    width: 96px; height: 96px; border-radius: 50%;
    background: radial-gradient(circle at 30% 30%, #2a3045, #1a1b26);
    box-shadow: 0 0 0 2px #9ece6a inset, 0 0 30px -6px rgba(158,206,106,.55);
    display: grid; place-items: center; color: #9ece6a;
    animation: pop .35s cubic-bezier(.18,.89,.32,1.28);
  }
  .check.pending { box-shadow: 0 0 0 2px #565f89 inset; color: #565f89; animation: spin 1.2s linear infinite; }
  @keyframes pop { from { transform: scale(.2); opacity: 0; } to { transform: scale(1); opacity: 1; } }
  @keyframes spin { to { transform: rotate(360deg); } }

  .ok-wrap h1 { margin: 0; font-size: 1.15rem; font-weight: 500; letter-spacing: .02em; color: #c0caf5; }
  .ok-wrap p { margin: 0; color: #9aa5ce; font-size: .92rem; text-align: center; }
  .ok-wrap code { color: #7dcfff; background: #15161e; padding: .18rem .5rem; border-radius: 5px; border: 1px solid #2a2f44; font-size: .88rem; }
  .ok-wrap .hint { color: #565f89; font-size: .85rem; margin-top: .3rem; }
  .back { color: #7aa2f7; text-decoration: none; font-size: .9rem; margin-top: .25rem; }
  .back:hover { color: #7dcfff; text-decoration: underline; }
</style>
</head>
<body>
<div class="card" id="root"></div>
<script>
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
    <div class="title"><b>claude</b>.mvr.ac</div>
    <div class="ok-wrap">
      <div class="check">${checkSvg()}</div>
      <h1>session ready</h1>
      <p><code>${esc(j.session)}</code></p>
      <p>${esc(j.dir)}</p>
      <p class="hint">${esc(j.msg)} — open the claude app to attach</p>
      <a class="back" href="/">← spawn another</a>
    </div>
  `;
}

function renderSpawning(dir) {
  root.innerHTML = `
    <div class="title"><b>claude</b>.mvr.ac</div>
    <div class="ok-wrap">
      <div class="check pending">${spinSvg()}</div>
      <h1>spawning…</h1>
      <p>${esc(dir)}</p>
    </div>
  `;
}

function renderError(msg) {
  root.innerHTML = `
    <div class="title"><b>claude</b>.mvr.ac</div>
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

async function renderPicker(path) {
  const r = await fetch('/api/list?path=' + encodeURIComponent(path));
  const j = await r.json();
  if (!j.ok) { renderError(j.error || 'list failed'); return; }
  const rows = [];
  if (j.parent) {
    rows.push(`<a class="row up" href="#${encodeURIComponent(j.parent)}"><span class="ico">↑</span><span class="name">..</span></a>`);
  }
  for (const e of j.entries) {
    const sub = (j.path.endsWith('/') ? j.path : j.path + '/') + e.name;
    rows.push(`<a class="row" data-name="${esc(e.name.toLowerCase())}" href="#${encodeURIComponent(sub)}"><span class="ico">▸</span><span class="name">${esc(e.name)}</span><span class="arrow">→</span></a>`);
  }
  if (!j.entries.length && !j.parent) {
    rows.push('<div class="empty">(no subdirectories)</div>');
  }
  root.innerHTML = `
    <div class="title"><b>claude</b>.mvr.ac</div>
    <div class="crumb">${crumbHtml(j.path)}</div>
    <button class="open-here" id="openHere"><span style="color:#9ece6a">▸</span><span>open <b>this</b> directory in claude</span></button>
    <input class="filter" id="filter" placeholder="filter subdirs…" autocomplete="off" autofocus>
    <div class="list" id="list">${rows.join('')}</div>
  `;
  document.getElementById('openHere').onclick = () => spawn(j.path);
  const filter = document.getElementById('filter');
  const list = document.getElementById('list');
  filter.addEventListener('input', () => {
    const q = filter.value.toLowerCase();
    list.querySelectorAll('.row').forEach(r => {
      const name = r.dataset.name || '';
      r.style.display = (!name || name.includes(q)) ? '' : 'none';
    });
  });
  filter.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      const first = list.querySelector('.row:not([style*="display: none"])');
      if (first) location.hash = first.getAttribute('href').slice(1);
    }
  });
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
</script>
</body>
</html>
"""


async def index(req: web.Request) -> web.Response:
    html = INDEX_HTML.replace("__HOME_JSON__", json.dumps(str(HOME)))
    return web.Response(text=html, content_type="text/html")


def main() -> None:
    app = web.Application()
    app.router.add_get("/", index)
    app.router.add_get("/api/list", api_list)
    app.router.add_post("/api/launch", api_launch)
    web.run_app(app, host=LISTEN_HOST, port=LISTEN_PORT, access_log=None, print=lambda *_: None)


if __name__ == "__main__":
    main()
