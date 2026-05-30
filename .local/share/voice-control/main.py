import asyncio
import json
import logging
import os
import shutil
import subprocess
from pathlib import Path

from aiohttp import web

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("voice-control")

HOST = os.environ.get("VOICE_CONTROL_HOST", "0.0.0.0")
PORT = int(os.environ.get("VOICE_CONTROL_PORT", "8094"))
PRESETS_DIR = Path(os.environ.get("VOICE_CONTROL_PRESETS_DIR", os.path.expanduser("~/.local/share/easyeffects/input")))
STATIC_DIR = Path(os.environ.get("VOICE_CONTROL_STATIC_DIR", str(Path(__file__).parent / "static")))
STATE_FILE = Path(os.environ.get("VOICE_CONTROL_STATE_FILE", os.path.expanduser("~/.local/state/voice-control/state.json")))
PRESET_PREFIX = "voice-"
BYPASS_NAME = "voice-bypass"

def list_presets():
    if not PRESETS_DIR.is_dir():
        return []
    out = []
    for p in sorted(PRESETS_DIR.glob(f"{PRESET_PREFIX}*.json")):
        out.append(p.stem)
    return out


def easyeffects_up():
    r = subprocess.run(
        ["systemctl", "--user", "is-active", "easyeffects"],
        capture_output=True, timeout=3,
    )
    return r.returncode == 0 and r.stdout.strip() == b"active"


def last_loaded_preset():
    r = subprocess.run(
        ["easyeffects", "--last-loaded-preset", "input"],
        capture_output=True, timeout=5,
    )
    if r.returncode != 0:
        return None
    name = r.stdout.decode().strip()
    return name or None


def load_preset(name):
    r = subprocess.run(
        ["easyeffects", "--load-preset", name],
        capture_output=True, timeout=5,
    )
    ok = r.returncode == 0
    return ok, (r.stderr or b"").decode().strip()


async def api_presets(_req):
    return web.json_response({"presets": list_presets(), "bypass": BYPASS_NAME})


async def api_status(_req):
    return web.json_response({
        "active": await asyncio.to_thread(last_loaded_preset),
        "easyeffects": await asyncio.to_thread(easyeffects_up),
        "presets_dir": str(PRESETS_DIR),
        "presets": list_presets(),
    })


async def api_load(req):
    name = req.match_info["name"]
    if name not in list_presets():
        return web.json_response({"error": f"unknown preset {name!r}"}, status=404)
    ok, info = await asyncio.to_thread(load_preset, name)
    if not ok:
        return web.json_response({"error": info}, status=500)
    return web.json_response({"active": name})


async def api_bypass(_req):
    if BYPASS_NAME not in list_presets():
        return web.json_response({"error": f"{BYPASS_NAME} preset missing"}, status=500)
    ok, info = await asyncio.to_thread(load_preset, BYPASS_NAME)
    if not ok:
        return web.json_response({"error": info}, status=500)
    return web.json_response({"active": BYPASS_NAME})


async def root(_req):
    index = STATIC_DIR / "index.html"
    if not index.is_file():
        return web.Response(status=500, text=f"missing {index}")
    return web.FileResponse(index)


def build_app():
    app = web.Application()
    app.router.add_get("/", root)
    app.router.add_get("/api/presets", api_presets)
    app.router.add_get("/api/status", api_status)
    app.router.add_post("/api/preset/{name}", api_load)
    app.router.add_post("/api/bypass", api_bypass)
    if STATIC_DIR.is_dir():
        app.router.add_static("/static/", STATIC_DIR, show_index=False)
    return app


def main():
    if not shutil.which("easyeffects"):
        log.warning("easyeffects not on PATH; preset loading will fail")
    log.info("listening on %s:%d (presets=%s)", HOST, PORT, PRESETS_DIR)
    web.run_app(build_app(), host=HOST, port=PORT, print=None)


if __name__ == "__main__":
    main()
