"""
claude.mvr.ac — add a tmux window running `claude` to the user's
current session and return a ✓. Picks the most-recently-active
attached session; falls back to any existing session; only spawns
a new session if tmux is empty.
"""
import asyncio
import os
from pathlib import Path

from aiohttp import web

HOME = Path(os.environ.get("HOME", "/home/m")).resolve()
LISTEN_HOST = os.environ.get("CLAUDE_WEB_HOST", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("CLAUDE_WEB_PORT", "7682"))
XDG_RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR", "/run/user/1000")
FALLBACK_SESSION = os.environ.get("CLAUDE_WEB_FALLBACK_SESSION", "claude")
EXCLUDE = {".git", "node_modules", "__pycache__", ".venv", ".direnv", ".cache", ".tmp"}


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


async def index(req: web.Request) -> web.Response:
    return web.FileResponse(STATIC_DIR / "index.html")


def main() -> None:
    app = web.Application()
    app.router.add_get("/", index)
    app.router.add_static("/static", STATIC_DIR)
    app.router.add_get("/api/list", api_list)
    app.router.add_get("/api/zoxide", api_zoxide)
    app.router.add_post("/api/launch", api_launch)
    web.run_app(app, host=LISTEN_HOST, port=LISTEN_PORT, access_log=None, print=lambda *_: None)


if __name__ == "__main__":
    main()
