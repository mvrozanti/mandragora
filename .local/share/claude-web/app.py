"""
claude.mvr.ac — fuzzy-pick a directory from the zoxide frecency
database and add a tmux window running `claude` there. Picks the
most-recently-active attached session; falls back to any existing
session; only spawns a new session if tmux is empty.
"""
import asyncio
import json
import os
import re
from pathlib import Path

from aiohttp import ClientSession, ClientTimeout, web

HOME = Path(os.environ.get("HOME", "/home/m")).resolve()
LISTEN_HOST = os.environ.get("CLAUDE_WEB_HOST", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("CLAUDE_WEB_PORT", "7682"))
XDG_RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR", "/run/user/1000")
FALLBACK_SESSION = os.environ.get("CLAUDE_WEB_FALLBACK_SESSION", "claude")
EXCLUDE = {".git", "node_modules", "__pycache__", ".venv", ".direnv", ".cache", ".tmp"}
THEME_URL = os.environ.get("CLAUDE_WEB_THEME_URL", "http://127.0.0.1:6684/api/theme?colors=1")
HTTP = web.AppKey("http", ClientSession)
SESSIONS_DIR = HOME / ".claude" / "sessions"
BRIDGE_URL = "https://claude.ai/code/{}"
PANE_RE = re.compile(r"%\d+")
CLAUDE_CMD = ("claude", "--remote-control")


STATIC_DIR = Path(__file__).parent / "static"


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


async def tmux_spawn(target: Path) -> tuple[bool, str, str, str | None]:
    env = {**os.environ, "XDG_RUNTIME_DIR": XDG_RUNTIME_DIR, "HOME": str(HOME)}
    session = await pick_session(env)
    name = target.name or target.anchor.strip("/") or "claude"

    if session is not None:
        rc, out, err = await tmux(
            "new-window", "-t", f"{session}:", "-c", str(target),
            "-n", name, "-P", "-F", "#{window_index} #{pane_id}", *CLAUDE_CMD, env=env,
        )
        action = "added window"
    else:
        session = FALLBACK_SESSION
        rc, out, err = await tmux(
            "new-session", "-d", "-s", session, "-c", str(target),
            "-n", name, "-P", "-F", "#{window_index} #{pane_id}", *CLAUDE_CMD, env=env,
        )
        action = "spawned session"

    if rc != 0:
        return False, session, err.strip()[:500] or "tmux failed", None
    window, _, pane = (out.strip().splitlines() or ["?"])[-1].partition(" ")
    await tmux(
        "set-option", "-w", "-t", f"{session}:{window}",
        "@claude_dir", str(target), env=env,
    )
    return True, f"{session}:{window}", action, pane or None


def pid_alive(pid) -> bool:
    try:
        os.kill(int(pid), 0)
    except (TypeError, ValueError, ProcessLookupError):
        return False
    except PermissionError:
        return True
    return True


def find_bridge(pane: str) -> str | None:
    for f in SESSIONS_DIR.glob("*.json"):
        try:
            s = json.loads(f.read_text())
        except (OSError, ValueError):
            continue
        if not str(s.get("tmux", "")).endswith("." + pane):
            continue
        bridge = s.get("bridgeSessionId")
        if bridge and pid_alive(s.get("pid")):
            return bridge
    return None


def list_dirs(p: Path) -> list[dict]:
    with os.scandir(p) as it:
        names = []
        for e in it:
            if e.name in EXCLUDE or e.name.startswith(".cache"):
                continue
            try:
                if e.is_dir():
                    names.append(e.name)
            except OSError:
                continue
    return [{"name": n} for n in sorted(names, key=str.lower)]


async def api_list(req: web.Request) -> web.Response:
    raw = req.query.get("path", "")
    p = resolve_dir(raw)
    if not await asyncio.to_thread(p.is_dir):
        return web.json_response({"ok": False, "error": f"not a directory: {p}"}, status=400)
    try:
        entries = await asyncio.to_thread(list_dirs, p)
    except PermissionError as exc:
        return web.json_response({"ok": False, "error": str(exc)}, status=403)
    parent = str(p.parent) if p != p.parent else None
    return web.json_response({"ok": True, "path": str(p), "parent": parent, "entries": entries})


async def zoxide_bump(target: Path) -> None:
    try:
        proc = await asyncio.create_subprocess_exec(
            "zoxide", "add", str(target),
            stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL,
        )
        await proc.wait()
    except OSError:
        pass


async def api_zoxide(req: web.Request) -> web.Response:
    try:
        proc = await asyncio.create_subprocess_exec(
            "zoxide", "query", "--list", "--score", "--all",
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
        )
    except OSError as exc:
        return web.json_response({"ok": False, "error": str(exc)}, status=503)
    out, _ = await proc.communicate()
    entries = []
    for line in out.decode(errors="replace").splitlines():
        score_str, _, path_str = line.strip().partition(" ")
        path_str = path_str.strip()
        if not path_str:
            continue
        try:
            score = float(score_str)
        except ValueError:
            continue
        entries.append({"score": score, "path": path_str})
    return web.json_response({"ok": True, "home": str(HOME), "entries": entries})


async def api_theme(req: web.Request) -> web.Response:
    try:
        async with req.app[HTTP].get(THEME_URL) as r:
            body = await r.read()
            status = r.status
    except (OSError, asyncio.TimeoutError):
        return web.Response(status=204)
    return web.Response(body=body, status=status, content_type="application/json",
                        headers={"Cache-Control": "no-store"})


async def api_bridge(req: web.Request) -> web.Response:
    pane = req.query.get("pane", "")
    if not PANE_RE.fullmatch(pane):
        return web.json_response({"ok": False, "error": "bad pane id"}, status=400)
    bridge = await asyncio.to_thread(find_bridge, pane)
    return web.json_response({"ok": True, "url": BRIDGE_URL.format(bridge) if bridge else None})


async def api_launch(req: web.Request) -> web.Response:
    body = await req.json()
    target = resolve_dir(body.get("dir"))
    if not await asyncio.to_thread(target.is_dir):
        return web.json_response({"ok": False, "error": f"not a directory: {target}"}, status=400)
    ok, session, msg, pane = await tmux_spawn(target)
    if ok:
        await zoxide_bump(target)
    status = 200 if ok else 500
    return web.json_response({"ok": ok, "session": session, "pane": pane, "dir": str(target), "msg": msg}, status=status)


async def index(req: web.Request) -> web.Response:
    return web.FileResponse(STATIC_DIR / "index.html")


async def http_client(app: web.Application):
    app[HTTP] = ClientSession(timeout=ClientTimeout(total=3))
    yield
    await app[HTTP].close()


def main() -> None:
    app = web.Application()
    app.cleanup_ctx.append(http_client)
    app.router.add_get("/", index)
    app.router.add_static("/static", STATIC_DIR)
    app.router.add_get("/api/list", api_list)
    app.router.add_get("/api/zoxide", api_zoxide)
    app.router.add_get("/api/theme", api_theme)
    app.router.add_get("/api/bridge", api_bridge)
    app.router.add_post("/api/launch", api_launch)
    web.run_app(app, host=LISTEN_HOST, port=LISTEN_PORT, access_log=None, print=lambda *_: None)


if __name__ == "__main__":
    main()
