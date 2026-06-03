#!/usr/bin/env python3
"""rgb-control — single-page RGB web UI for Mandragora.

Backend: rgb-control owns a long-running `openrgb --server` child
process and talks to it via the OpenRGB Python SDK. RAM + motherboard
use a "safe" config dir; mouse + keyboard need HID detectors that
conflict with keyledsd, gated behind a takeover toggle — toggling
respawns the child with the alternate `--config` dir. Recovery is
layered: panic button restores keyledsd, ExecStopPost too, startup
forces override=off.

Setbg / wal-to-rgb / wal-to-rgb-daemon all connect to the same
openrgb server on the SDK default port (6742); rgb-control is the
only writer that owns its lifecycle.

Frontend: single page, all device classes, live swatches showing the
last-applied colour per device, debounced auto-apply on every control
change, scene presets that fan out across every class.
"""
from __future__ import annotations

import asyncio
import json
import logging
import os
import re
import shutil
import socket
import time
from pathlib import Path
from typing import Any

from aiohttp import web

from openrgb import OpenRGBClient
from openrgb.utils import RGBColor

log = logging.getLogger("rgb-control")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")

OPENRGB = shutil.which("openrgb") or "openrgb"
SYSTEMCTL = shutil.which("systemctl") or "/run/current-system/sw/bin/systemctl"

STATE_DIR = Path("/persistent/mandragora/.local/share/rgb-control")
STATE_FILE = STATE_DIR / "state.json"

HOME = Path(os.environ.get("HOME", "/home/m"))
SAFE_CONFIG = HOME / ".config" / "OpenRGB"
HID_CONFIG = HOME / ".config" / "OpenRGB-rgb-web-hid"

HID_DETECTORS = [
    "SteelSeries Rival 3",
    "SteelSeries Rival 3 (Old Firmware)",
    "Logitech G Pro RGB Mechanical Gaming Keyboard",
]

KEYLEDS_UNITS = ["keyledsd.service", "keyleds-workspace-watcher.service"]

DEVICE_CLASSES = {
    "ram":      {"type": "DRAM",        "label": "RAM",         "hid": False},
    "mobo":     {"type": "Motherboard", "label": "Motherboard", "hid": False},
    "mouse":    {"type": "Mouse",       "label": "Mouse",       "hid": True},
    "keyboard": {"type": "Keyboard",    "label": "Keyboard",    "hid": True},
}

SERVER_HOST = "127.0.0.1"
SERVER_PORT = 6742

_openrgb_lock = asyncio.Lock()
_server: asyncio.subprocess.Process | None = None
_client: OpenRGBClient | None = None
_current_config: Path | None = None


def load_state() -> dict[str, Any]:
    try:
        s = json.loads(STATE_FILE.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        s = {}
    s.setdefault("override", False)
    last = s.setdefault("last", {})
    for k in DEVICE_CLASSES:
        last.setdefault(k, {})
    return s


def save_state(state: dict[str, Any]) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state))


def ensure_hid_config() -> Path:
    safe_json = SAFE_CONFIG / "OpenRGB.json"
    if not safe_json.exists():
        raise RuntimeError(f"safe openrgb config missing: {safe_json}")
    HID_CONFIG.mkdir(parents=True, exist_ok=True)
    cfg = json.loads(safe_json.read_text())
    detectors = cfg.setdefault("Detectors", {}).setdefault("detectors", {})
    for name in HID_DETECTORS:
        if name in detectors:
            detectors[name] = True
    (HID_CONFIG / "OpenRGB.json").write_text(json.dumps(cfg, indent=4))
    log.info("hid openrgb config refreshed at %s", HID_CONFIG)
    return HID_CONFIG


async def run_systemctl_user(verb: str, unit: str) -> tuple[int, str]:
    proc = await asyncio.create_subprocess_exec(
        SYSTEMCTL, "--user", verb, unit,
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT,
    )
    out, _ = await proc.communicate()
    return proc.returncode, out.decode(errors="replace")


async def stop_keyleds() -> str:
    msgs = []
    for unit in KEYLEDS_UNITS:
        rc, out = await run_systemctl_user("stop", unit)
        msgs.append(f"stop {unit}: rc={rc} {out.strip()}")
    return "\n".join(msgs)


async def restart_keyleds() -> str:
    msgs = []
    for unit in KEYLEDS_UNITS:
        rc, out = await run_systemctl_user("restart", unit)
        msgs.append(f"restart {unit}: rc={rc} {out.strip()}")
    return "\n".join(msgs)


def config_dir_for_state(hid_enabled: bool) -> Path:
    return HID_CONFIG if hid_enabled else SAFE_CONFIG


def _port_open(host: str, port: int) -> bool:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(0.25)
    try:
        s.connect((host, port))
        return True
    except OSError:
        return False
    finally:
        s.close()


async def _wait_port(host: str, port: int, timeout: float = 8.0) -> None:
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if _port_open(host, port):
            return
        await asyncio.sleep(0.15)
    raise TimeoutError(f"openrgb server did not bind {host}:{port} within {timeout}s")


async def _stop_server() -> None:
    global _server, _client
    if _client is not None:
        try:
            _client.disconnect()
        except Exception:
            pass
        _client = None
    if _server is not None and _server.returncode is None:
        try:
            _server.terminate()
            await asyncio.wait_for(_server.wait(), timeout=3.0)
        except asyncio.TimeoutError:
            _server.kill()
            await _server.wait()
        except ProcessLookupError:
            pass
    _server = None


async def _start_server(hid_enabled: bool) -> None:
    global _server, _current_config
    if hid_enabled:
        try:
            ensure_hid_config()
        except Exception as e:
            log.warning("ensure_hid_config failed before server start: %s", e)
    config_dir = config_dir_for_state(hid_enabled)
    log.info("spawning openrgb --server --config %s", config_dir)
    _server = await asyncio.create_subprocess_exec(
        OPENRGB, "--server", "--server-host", SERVER_HOST,
        "--server-port", str(SERVER_PORT),
        "--noautoconnect", "--config", str(config_dir),
        stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL,
    )
    _current_config = config_dir
    await _wait_port(SERVER_HOST, SERVER_PORT)


async def _ensure_client() -> OpenRGBClient:
    global _client
    override = bool(load_state().get("override"))
    desired = config_dir_for_state(override)
    needs_restart = (
        _server is None
        or _server.returncode is not None
        or _current_config != desired
    )
    if needs_restart:
        await _stop_server()
        await _start_server(override)
    if _client is None:
        _client = OpenRGBClient(address=SERVER_HOST, port=SERVER_PORT, name="rgb-control")
    else:
        try:
            _client.update()
        except Exception:
            try: _client.disconnect()
            except Exception: pass
            _client = OpenRGBClient(address=SERVER_HOST, port=SERVER_PORT, name="rgb-control")
    return _client


def _zone_led_count(zone) -> int:
    try:
        return len(zone.leds)
    except Exception:
        return getattr(zone, "leds_count", 0) or 0


async def list_devices_for_class(cls: str) -> list[dict[str, Any]]:
    info = DEVICE_CLASSES[cls]
    if info["hid"] and not load_state().get("override"):
        return []
    async with _openrgb_lock:
        try:
            client = await _ensure_client()
        except Exception as e:
            log.warning("ensure_client failed: %s", e)
            return []
        target = info["type"].lower()
        out: list[dict[str, Any]] = []
        for idx, dev in enumerate(client.devices):
            try:
                dtype = dev.device_type.name.lower()
            except Exception:
                dtype = ""
            if dtype != target:
                continue
            zones = [z.name for z in dev.zones if _zone_led_count(z) > 0]
            modes = [m.name for m in dev.modes]
            out.append({
                "index": idx,
                "name": dev.name,
                "type": dev.device_type.name,
                "modes": modes,
                "zones": zones,
            })
        return out


async def devices_for_class(cls: str) -> list[dict[str, Any]]:
    return await list_devices_for_class(cls)


_HEX_COLOR = re.compile(r"^[0-9A-Fa-f]{6}$")


def _normalize_color(c: str | None) -> str | None:
    if c is None:
        return None
    c = c.strip().lstrip("#")
    if not _HEX_COLOR.match(c):
        return None
    return c.upper()


def _find_mode(dev, name: str):
    target = name.lower()
    for m in dev.modes:
        if m.name.lower() == target:
            return m
    return None


def _scale_pct(pct: int, lo: int, hi: int) -> int:
    if hi <= lo:
        return lo
    return int(lo + (hi - lo) * max(0, min(100, pct)) / 100)


async def _apply_one(cls: str, device_idx: int, mode: str, color: str | None,
                     zone: str | int | None, speed: str | int | None,
                     brightness: str | int | None) -> tuple[int, str]:
    async with _openrgb_lock:
        try:
            client = await _ensure_client()
        except Exception as e:
            return 500, f"openrgb server unreachable: {e}"
        try:
            dev = client.devices[device_idx]
        except IndexError:
            return 404, f"device index {device_idx} out of range"

        m = _find_mode(dev, mode)
        if m is None:
            return 400, f"device has no mode named {mode!r}"

        try:
            if brightness not in (None, "") and getattr(m, "brightness_max", 0):
                m.brightness = _scale_pct(int(brightness), m.brightness_min, m.brightness_max)
            if speed not in (None, "") and getattr(m, "speed_max", 0):
                m.speed = _scale_pct(int(speed), m.speed_min, m.speed_max)
        except Exception as e:
            log.info("brightness/speed not applied: %s", e)

        log.info("apply: dev=%d %r mode=%s color=%s zone=%s",
                 device_idx, dev.name, mode, color, zone)
        try:
            dev.set_mode(m)
        except Exception as e:
            return 500, f"set_mode failed: {e}"

        if color:
            try:
                rgb = RGBColor.fromHEX("#" + color)
            except Exception:
                return 400, f"bad color {color!r}"
            try:
                if zone not in (None, ""):
                    zi = int(zone)
                    zones_to_set = [dev.zones[zi]] if 0 <= zi < len(dev.zones) else []
                else:
                    zones_to_set = list(dev.zones)
                for z in zones_to_set:
                    n = _zone_led_count(z)
                    if n > 0:
                        z.set_colors([rgb] * n)
            except Exception as e:
                return 500, f"set_colors failed: {e}"

        try:
            dev.show()
        except Exception as e:
            log.info("dev.show ignored: %s", e)
        return 200, "ok"


def _record_apply(cls: str, idx: int, settings: dict[str, Any]) -> None:
    state = load_state()
    state["last"].setdefault(cls, {})[str(idx)] = {
        **settings,
        "ts": int(time.time()),
    }
    save_state(state)


async def apply_settings(payload: dict[str, Any]) -> tuple[int, str]:
    cls = payload.get("class")
    if cls not in DEVICE_CLASSES:
        return 400, f"unknown class: {cls}"
    info = DEVICE_CLASSES[cls]
    if info["hid"] and not load_state().get("override"):
        return 409, "mouse/keyboard takeover required — enable it first"
    mode = (payload.get("mode") or "").strip()
    if not mode:
        return 400, "missing mode"
    color = _normalize_color(payload.get("color"))
    zone = payload.get("zone")
    speed = payload.get("speed")
    brightness = payload.get("brightness")

    device_raw = (str(payload.get("device") or "")).strip()
    if device_raw == "":
        targets = [d["index"] for d in await devices_for_class(cls)]
        if not targets:
            return 404, "no devices in this class"
    else:
        try:
            targets = [int(device_raw)]
        except ValueError:
            return 400, f"device must be an index, got: {device_raw!r}"

    record = {"mode": mode, "color": color, "zone": zone, "speed": speed, "brightness": brightness}

    overall_rc = 200
    msgs = []
    for idx in targets:
        rc, body = await _apply_one(cls, idx, mode, color, zone, speed, brightness)
        msgs.append(f"[device {idx}] rc={rc} {body}".rstrip())
        if rc != 200:
            overall_rc = rc if overall_rc == 200 else overall_rc
        else:
            _record_apply(cls, idx, record)
    return overall_rc, "\n".join(msgs)[-1200:]


async def apply_bulk(payload: dict[str, Any]) -> tuple[int, str]:
    items = payload.get("items") or []
    if not items:
        return 400, "no items"
    override = bool(load_state().get("override"))
    runnable: list[tuple[str, dict[str, Any]]] = []
    skipped: list[str] = []
    for item in items:
        cls = item.get("class")
        if cls not in DEVICE_CLASSES:
            skipped.append(f"{cls}: unknown")
            continue
        if DEVICE_CLASSES[cls]["hid"] and not override:
            skipped.append(f"{cls}: takeover off")
            continue
        runnable.append((cls, item))
    if not runnable:
        return 409, "nothing applied (takeover required for mouse/keyboard?)\n" + "\n".join(skipped)
    rcs = await asyncio.gather(*(apply_settings(item) for _, item in runnable))
    overall = 200 if all(rc == 200 for rc, _ in rcs) else 500
    summary = [f"{cls}: rc={rc}" for (cls, _), (rc, _) in zip(runnable, rcs)]
    if skipped:
        summary += [f"skipped {s}" for s in skipped]
    return overall, "\n".join(summary)


async def set_override(enabled: bool) -> str:
    state = load_state()
    state["override"] = bool(enabled)
    save_state(state)
    msgs = []
    if enabled:
        msgs.append(await stop_keyleds())
    else:
        msgs.append(await restart_keyleds())
    async with _openrgb_lock:
        try:
            await _stop_server()
            await _start_server(enabled)
        except Exception as e:
            log.warning("respawn openrgb server failed: %s", e)
            msgs.append(f"server respawn failed: {e}")
    return "\n".join(msgs)


async def startup_recovery(app: web.Application) -> None:
    try:
        ensure_hid_config()
    except Exception as e:
        log.warning("ensure_hid_config failed: %s", e)
    state = load_state()
    if state.get("override"):
        log.info("override=on at start — stopping keyledsd to match")
        await stop_keyleds()
    else:
        log.info("override=off at start — ensuring keyledsd is up")
        await restart_keyleds()
    async with _openrgb_lock:
        try:
            await _stop_server()
            await _start_server(bool(state.get("override")))
        except Exception as e:
            log.error("openrgb server failed to start: %s", e)


async def shutdown_cleanup(app: web.Application) -> None:
    async with _openrgb_lock:
        await _stop_server()


# ---------------------------------------------------------------- frontend

STYLE = """
:root {
  --bg: #06090a; --panel: #0c1216; --panel-2: #101820;
  --fg: #e6f0f3; --dim: #6b8088; --line: #1c2830; --hover: #18242e;
  --accent: #00ff88; --accent-soft: rgba(0,255,136,0.16);
  --warn: #ff6b6b; --warn-bg: #2a0d0d; --warm: #ffb347;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
html, body { background: var(--bg); color: var(--fg);
  font: 14px/1.45 ui-monospace, "Iosevka", "JetBrains Mono", monospace; }
body { min-height: 100vh; padding: 1.4rem clamp(0.75rem, 4vw, 2rem) 5rem; }
a { color: var(--accent); text-decoration: none; }
a:hover { text-decoration: underline; }
.wrap { max-width: 1100px; margin: 0 auto; display: flex; flex-direction: column; gap: 1.1rem; }

header.top { display: flex; justify-content: space-between; align-items: center;
  gap: 1rem; flex-wrap: wrap; padding-bottom: 1rem; border-bottom: 1px solid var(--line); }
.title h1 { font-size: 1.45rem; font-weight: 600; letter-spacing: 0.04em; color: var(--accent); }
.title h1::before { content: "$ "; color: var(--dim); font-weight: 400; }
.title .sub { color: var(--dim); font-size: 0.72rem; letter-spacing: 0.22em;
  text-transform: uppercase; margin-top: 0.2rem; }
.panic { background: transparent; color: var(--warn); border: 1px solid var(--warn);
  padding: 0.55rem 1rem; font: inherit; cursor: pointer; letter-spacing: 0.05em;
  text-transform: lowercase; transition: 0.12s; }
.panic:hover { background: var(--warn); color: var(--bg); }

section.card { background: var(--panel); border: 1px solid var(--line); padding: 1rem 1.1rem; }
section.card > h2 { font-size: 0.72rem; letter-spacing: 0.22em; text-transform: uppercase;
  color: var(--dim); margin-bottom: 0.85rem; font-weight: 500; }

.scenes .scene-buttons { display: flex; flex-wrap: wrap; gap: 0.5rem; }
.scene-btn { background: var(--panel-2); color: var(--fg); border: 1px solid var(--line);
  padding: 0.55rem 0.9rem; font: inherit; cursor: pointer; transition: 0.12s;
  display: inline-flex; gap: 0.5rem; align-items: center; letter-spacing: 0.02em; }
.scene-btn:hover { border-color: var(--accent); background: var(--hover); color: var(--accent); }
.scene-btn .swatch { width: 14px; height: 14px; border: 1px solid rgba(255,255,255,0.18);
  flex: 0 0 14px; border-radius: 2px; }
.scenes .scene-color { display: flex; gap: 0.6rem; align-items: center; padding-top: 0.9rem;
  margin-top: 0.85rem; border-top: 1px dashed var(--line); flex-wrap: wrap; }
.scenes .scene-color label { color: var(--dim); font-size: 0.72rem; letter-spacing: 0.1em;
  text-transform: uppercase; }
.scenes input[type=color] { width: 72px; height: 36px; background: var(--panel-2);
  border: 1px solid var(--line); padding: 0; cursor: pointer; }
.scenes .scene-color .apply-all { background: var(--accent); color: var(--bg); border: 1px solid var(--accent);
  padding: 0.6rem 1.1rem; font: inherit; cursor: pointer; font-weight: 600; letter-spacing: 0.04em; }
.scenes .scene-color .apply-all:hover { filter: brightness(1.12); }

.takeover { display: flex; justify-content: space-between; align-items: center;
  gap: 1rem; flex-wrap: wrap; transition: 0.12s; }
.takeover-info strong { color: var(--fg); font-size: 0.95rem; display: block; margin-bottom: 0.3rem; }
.takeover-info p { color: var(--dim); font-size: 0.8rem; max-width: 640px; line-height: 1.5; }
.takeover-info p em { color: var(--warn); font-style: normal; }
.takeover .switch { background: var(--panel-2); color: var(--fg); border: 1px solid var(--line);
  padding: 0.7rem 1.4rem; font: inherit; cursor: pointer; letter-spacing: 0.08em;
  text-transform: uppercase; font-size: 0.74rem; min-width: 140px; }
.takeover .switch:hover { border-color: var(--accent); }
.takeover.on { border-color: var(--warm);
  background: linear-gradient(180deg, rgba(255,179,71,0.06), var(--panel)); }
.takeover.on .takeover-info strong { color: var(--warm); }
.takeover.on .switch { background: var(--warm); color: var(--bg); border-color: var(--warm); }

.classes { display: flex; flex-direction: column; gap: 1.1rem; }

.class-panel { background: var(--panel); border: 1px solid var(--line); padding: 1rem 1.1rem;
  transition: 0.16s; }
.class-panel.locked { opacity: 0.7; border-style: dashed; }
.class-panel.empty { opacity: 0.55; }
.class-panel header { display: flex; justify-content: space-between; align-items: baseline;
  margin-bottom: 0.9rem; border: none; padding: 0; flex-wrap: wrap; gap: 0.5rem; }
.class-panel header h2 { color: var(--fg); font-size: 1rem; font-weight: 600;
  letter-spacing: 0; text-transform: none; display: flex; align-items: baseline; gap: 0.6rem; }
.class-panel header h2 small { color: var(--dim); font-size: 0.74rem; font-weight: 400; }
.class-panel header .status-pill { color: var(--dim); font-size: 0.7rem; letter-spacing: 0.12em;
  text-transform: uppercase; padding: 0.18rem 0.55rem; border: 1px solid var(--line); }
.class-panel.locked header .status-pill { color: var(--warm); border-color: var(--warm); }

.locked-msg { color: var(--warm); font-size: 0.82rem; padding: 0.75rem 0.9rem;
  border: 1px dashed var(--warm); background: rgba(255,179,71,0.06); }
.empty-msg { color: var(--dim); font-size: 0.82rem; padding: 0.75rem 0.9rem;
  border: 1px dashed var(--line); background: var(--panel-2); }

.device-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(130px, 1fr));
  gap: 0.55rem; margin-bottom: 0.95rem; }
.dev-tile { background: var(--panel-2); border: 1px solid var(--line); padding: 0.7rem 0.6rem;
  font: inherit; color: var(--fg); cursor: pointer; text-align: left;
  display: flex; flex-direction: column; gap: 0.4rem; transition: 0.1s; overflow: hidden; }
.dev-tile:hover { border-color: var(--dim); }
.dev-tile.selected { border-color: var(--accent); background: var(--hover);
  box-shadow: 0 0 0 1px var(--accent-soft); }
.dev-tile .dot { width: 100%; height: 30px; border: 1px solid rgba(255,255,255,0.06);
  background: repeating-linear-gradient(45deg, #1a1a1a 0 6px, #222 6px 12px); }
.dev-tile .name { font-size: 0.82rem; color: var(--fg); display: flex; gap: 0.35rem;
  align-items: baseline; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.dev-tile .idx { color: var(--dim); font-size: 0.7rem; }
.dev-tile .meta { font-size: 0.7rem; color: var(--dim); white-space: nowrap;
  overflow: hidden; text-overflow: ellipsis; }
.dev-tile.all .dot { background: linear-gradient(90deg, #ff3355 0%, #ffaa33 25%, #44ff66 50%, #44aaff 75%, #aa55ff 100%); }

.controls { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
  gap: 0.7rem 1.1rem; align-items: center; padding-top: 0.7rem;
  border-top: 1px solid var(--line); }
.row { display: flex; gap: 0.55rem; align-items: center; }
.row label { color: var(--dim); font-size: 0.7rem; text-transform: uppercase;
  letter-spacing: 0.12em; min-width: 72px; }
.row select, .row input[type=range] {
  background: var(--panel-2); border: 1px solid var(--line); color: var(--fg);
  font: inherit; padding: 0.4rem 0.55rem; flex: 1; min-width: 0;
}
.row select:focus, .row input:focus { outline: none; border-color: var(--accent); }
.row input[type=color] { width: 48px; height: 34px; flex: 0 0 48px; padding: 0;
  background: var(--panel-2); border: 1px solid var(--line); cursor: pointer; }
.row input[type=range] { padding: 0; accent-color: var(--accent); }
.row .val { color: var(--accent); font-size: 0.78rem; min-width: 32px; text-align: right;
  font-variant-numeric: tabular-nums; }
.row.hidden { display: none; }

#toast { position: fixed; bottom: 1.2rem; right: 1.2rem; max-width: 360px;
  padding: 0.8rem 1rem; background: var(--panel-2); border: 1px solid var(--line);
  color: var(--fg); font-size: 0.82rem; transform: translateY(8px); opacity: 0;
  transition: 0.16s; pointer-events: none; white-space: pre-wrap;
  font-family: ui-monospace, monospace; max-height: 50vh; overflow: hidden; z-index: 10; }
#toast.show { transform: translateY(0); opacity: 1; }
#toast.ok { border-color: var(--accent); color: var(--accent); }
#toast.err { border-color: var(--warn); color: var(--warn); }

footer.foot { color: var(--dim); font-size: 0.7rem; letter-spacing: 0.08em;
  text-align: center; padding-top: 0.5rem; }
footer.foot code { color: var(--accent); font-size: 0.7rem; }

@media (max-width: 540px) {
  .controls { grid-template-columns: 1fr; }
  .row label { min-width: 60px; font-size: 0.66rem; }
  .title h1 { font-size: 1.2rem; }
}
"""


def _index_html() -> str:
    cls_meta = {k: {"label": v["label"], "hid": v["hid"]} for k, v in DEVICE_CLASSES.items()}
    return f"""<!DOCTYPE html>
<html lang="en"><head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>rgb · mvr.ac</title><style>{STYLE}</style>
</head><body><div class="wrap">

<header class="top">
  <div class="title">
    <h1>rgb</h1>
    <div class="sub">RGB control · mvr.ac</div>
  </div>
  <button class="panic" id="panic">restore keyleds</button>
</header>

<section class="card scenes">
  <h2>quick scenes</h2>
  <div class="scene-buttons" id="scene-buttons"></div>
  <div class="scene-color">
    <label for="scene-color">paint everything</label>
    <input type="color" id="scene-color" value="#00ff88">
    <button class="apply-all" id="apply-color-all">apply to all devices</button>
  </div>
</section>

<section class="card takeover" id="takeover">
  <div class="takeover-info">
    <strong id="takeover-title">keyboard + mouse</strong>
    <p>OFF: per-key keyledsd effects run normally. ON: openrgb takes over the keyboard and mouse via HID, keyledsd is paused. Toggle back OFF (or hit <em>restore keyleds</em> top-right) to return to normal.</p>
  </div>
  <button class="switch" id="override">enable</button>
</section>

<div class="classes" id="classes"></div>

<footer class="foot">openrgb SDK · server on 127.0.0.1:6742 · GET <code>/api/state-full</code> · POST <code>/api/apply-bulk</code></footer>

</div>
<div id="toast"></div>

<script>
const CLASSES = {json.dumps(cls_meta)};
const ANIM_RE = /wave|cycle|breath|pulse|rainbow|spectrum|flash|blink|chase|fade|sweep|move|drip|rain/i;
const NEEDS_SPEED = (mode) => ANIM_RE.test(mode || "");
const NO_COLOR_RE = /^(off|spectrum|cycle|rainbow|random)/i;
const NEEDS_COLOR = (mode) => !NO_COLOR_RE.test(mode || "");
const SCENES = [
  {{ id: "off",      label: "off",      swatch: "#000000", mode: "Off",      fallback: ["Direct", "Static"], color: "#000000", noColor: true }},
  {{ id: "white",    label: "white",    swatch: "#ffffff", mode: "Static",   color: "#ffffff" }},
  {{ id: "red",      label: "red",      swatch: "#ff2233", mode: "Static",   color: "#ff2233" }},
  {{ id: "amber",    label: "amber",    swatch: "#ffaa22", mode: "Static",   color: "#ffaa22" }},
  {{ id: "green",    label: "green",    swatch: "#00ff66", mode: "Static",   color: "#00ff66" }},
  {{ id: "cyan",     label: "cyan",     swatch: "#22ccff", mode: "Static",   color: "#22ccff" }},
  {{ id: "blue",     label: "blue",     swatch: "#3366ff", mode: "Static",   color: "#3366ff" }},
  {{ id: "magenta",  label: "magenta",  swatch: "#ff33aa", mode: "Static",   color: "#ff33aa" }},
  {{ id: "rainbow",  label: "rainbow",
                    swatch: "linear-gradient(90deg,#f00,#ff0,#0f0,#0ff,#00f,#f0f)",
                    modes: ["Rainbow Wave", "Spectrum Cycle", "Rainbow", "Cycle"],
                    fallback: ["Static"] }},
  {{ id: "breathing",label: "breathing",swatch: "#00ff88",
                    modes: ["Breathing", "Pulse", "Pulsing"],
                    fallback: ["Static"], color: "#00ff88" }},
];

const $ = (s, r=document) => r.querySelector(s);

const state = {{
  override: false,
  devicesByClass: {{}},
  lastByClass: {{}},
  selectedByClass: {{}},
}};

function toast(msg, kind) {{
  const el = $('#toast');
  el.textContent = msg;
  el.className = 'show ' + (kind || '');
  clearTimeout(toast._t);
  toast._t = setTimeout(() => el.className = '', 2600);
}}

async function api(path, opts) {{
  const r = await fetch(path, opts || {{}});
  const ct = r.headers.get('content-type') || '';
  const body = ct.includes('json') ? await r.json() : await r.text();
  return {{ ok: r.ok, status: r.status, body }};
}}

class Debouncer {{
  constructor(delay) {{ this.delay = delay; this.timer = null; this.ctrl = null; }}
  run(fn) {{
    clearTimeout(this.timer);
    this.timer = setTimeout(async () => {{
      if (this.ctrl) this.ctrl.abort();
      this.ctrl = new AbortController();
      try {{ await fn(this.ctrl.signal); }} catch (e) {{
        if (e.name !== 'AbortError') console.error(e);
      }}
    }}, this.delay);
  }}
}}

function pickMode(modes, preferred, fallback) {{
  const lower = (modes || []).map(m => m.toLowerCase());
  for (const p of (preferred || [])) {{
    const i = lower.indexOf(p.toLowerCase());
    if (i >= 0) return modes[i];
  }}
  for (const f of (fallback || [])) {{
    const i = lower.indexOf(f.toLowerCase());
    if (i >= 0) return modes[i];
  }}
  return modes && modes.length ? modes[0] : null;
}}

function hexFromLast(c) {{ return c ? ('#' + c) : null; }}
function selectedIdx(cls) {{
  const sel = state.selectedByClass[cls];
  return (sel === undefined || sel === null) ? 'all' : sel;
}}
function shortName(s) {{ return s.length > 26 ? s.slice(0, 23) + '...' : s; }}
function escapeHtml(s) {{
  return s.replace(/[&<>"]/g, c => ({{ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;' }})[c]);
}}

function renderSceneButtons() {{
  const row = $('#scene-buttons');
  row.innerHTML = '';
  for (const s of SCENES) {{
    const b = document.createElement('button');
    b.className = 'scene-btn';
    b.innerHTML = '<span class="swatch" style="background:' + s.swatch + '"></span>' + s.label;
    b.addEventListener('click', () => runScene(s));
    row.appendChild(b);
  }}
}}

function renderTakeover() {{
  const row = $('#takeover');
  const btn = $('#override');
  const title = $('#takeover-title');
  if (state.override) {{
    row.classList.add('on');
    btn.textContent = 'disable';
    title.textContent = 'takeover ON · keyledsd paused';
  }} else {{
    row.classList.remove('on');
    btn.textContent = 'enable';
    title.textContent = 'keyboard + mouse';
  }}
}}

function activeDevicesForClass(cls) {{
  const devs = state.devicesByClass[cls] || [];
  const sel = selectedIdx(cls);
  if (sel === 'all') return devs;
  const d = devs.find(x => String(x.index) === String(sel));
  return d ? [d] : devs;
}}

function renderClasses() {{
  const root = $('#classes');
  root.innerHTML = '';
  for (const [cls, meta] of Object.entries(CLASSES)) {{
    const panel = document.createElement('section');
    panel.className = 'card class-panel';
    panel.dataset.cls = cls;
    const devs = state.devicesByClass[cls] || [];
    const last = state.lastByClass[cls] || {{}};
    const locked = meta.hid && !state.override;
    const empty = !locked && devs.length === 0;
    if (locked) panel.classList.add('locked');
    if (empty) panel.classList.add('empty');

    let status;
    if (locked) status = 'takeover required';
    else if (empty) status = 'no devices';
    else status = devs.length + ' device' + (devs.length === 1 ? '' : 's');

    const hdr = document.createElement('header');
    hdr.innerHTML =
      '<h2>' + meta.label + (locked || empty ? '' : ' <small>' + devs.length + ' detected</small>') + '</h2>' +
      '<span class="status-pill">' + status + '</span>';
    panel.appendChild(hdr);

    if (locked) {{
      const m = document.createElement('div');
      m.className = 'locked-msg';
      m.textContent = 'Enable keyboard + mouse takeover above to control ' + meta.label.toLowerCase() + '.';
      panel.appendChild(m);
      root.appendChild(panel);
      continue;
    }}
    if (empty) {{
      const m = document.createElement('div');
      m.className = 'empty-msg';
      m.textContent = 'openrgb did not find any ' + meta.label.toLowerCase() + ' devices.';
      panel.appendChild(m);
      root.appendChild(panel);
      continue;
    }}

    const grid = document.createElement('div');
    grid.className = 'device-grid';
    const sel = selectedIdx(cls);

    if (devs.length > 1) {{
      const all = document.createElement('button');
      all.className = 'dev-tile all' + (sel === 'all' ? ' selected' : '');
      all.innerHTML =
        '<div class="dot"></div>' +
        '<div class="name">all <span class="idx">(' + devs.length + ')</span></div>' +
        '<div class="meta">paint together</div>';
      all.addEventListener('click', () => selectDevice(cls, 'all'));
      grid.appendChild(all);
    }}

    for (const d of devs) {{
      const tile = document.createElement('button');
      const isSel = String(sel) === String(d.index);
      tile.className = 'dev-tile' + (isSel ? ' selected' : '');
      const lastDev = last[String(d.index)] || {{}};
      const dot = document.createElement('div');
      dot.className = 'dot';
      const swatch = hexFromLast(lastDev.color);
      if (lastDev.mode && /off/i.test(lastDev.mode)) {{
        dot.style.background = '#050505';
      }} else if (swatch && swatch !== '#000000') {{
        dot.style.background = swatch;
        dot.style.boxShadow = 'inset 0 0 14px rgba(0,0,0,0.45)';
      }}
      tile.appendChild(dot);
      const name = document.createElement('div');
      name.className = 'name';
      name.innerHTML = '<span class="idx">#' + d.index + '</span> ' + escapeHtml(shortName(d.name));
      tile.appendChild(name);
      const meta_ = document.createElement('div');
      meta_.className = 'meta';
      meta_.textContent = lastDev.mode || '—';
      tile.appendChild(meta_);
      tile.title = d.name;
      tile.addEventListener('click', () => selectDevice(cls, d.index));
      grid.appendChild(tile);
    }}

    panel.appendChild(grid);

    const ctl = buildControls(cls, devs, last);
    panel.appendChild(ctl);

    root.appendChild(panel);
  }}
}}

function buildControls(cls, devs, last) {{
  const wrap = document.createElement('div');
  wrap.className = 'controls';

  const sel = selectedIdx(cls);
  const active = activeDevicesForClass(cls);
  const sample = active[0] || devs[0];
  const lastDev = sel !== 'all'
    ? (last[String(sel)] || {{}})
    : (last[String(sample.index)] || {{}});

  const allModes = new Set();
  for (const d of active) (d.modes || []).forEach(m => allModes.add(m));

  const modeRow = document.createElement('div'); modeRow.className = 'row';
  modeRow.innerHTML = '<label>mode</label>';
  const modeSel = document.createElement('select');
  for (const m of allModes) {{
    const o = document.createElement('option');
    o.value = m; o.textContent = m;
    if (m === lastDev.mode) o.selected = true;
    modeSel.appendChild(o);
  }}
  modeRow.appendChild(modeSel);
  wrap.appendChild(modeRow);

  const colorRow = document.createElement('div'); colorRow.className = 'row color-row';
  colorRow.innerHTML = '<label>color</label>';
  const colorIn = document.createElement('input');
  colorIn.type = 'color';
  colorIn.value = lastDev.color ? ('#' + lastDev.color) : '#00ff88';
  colorRow.appendChild(colorIn);
  wrap.appendChild(colorRow);

  const briRow = document.createElement('div'); briRow.className = 'row';
  briRow.innerHTML = '<label>brightness</label>';
  const briIn = document.createElement('input');
  briIn.type = 'range'; briIn.min = '0'; briIn.max = '100';
  briIn.value = lastDev.brightness != null && lastDev.brightness !== '' ? lastDev.brightness : 100;
  const briVal = document.createElement('span'); briVal.className = 'val'; briVal.textContent = briIn.value;
  briRow.appendChild(briIn); briRow.appendChild(briVal);
  wrap.appendChild(briRow);

  const spRow = document.createElement('div'); spRow.className = 'row speed-row';
  spRow.innerHTML = '<label>speed</label>';
  const spIn = document.createElement('input');
  spIn.type = 'range'; spIn.min = '0'; spIn.max = '100';
  spIn.value = lastDev.speed != null && lastDev.speed !== '' ? lastDev.speed : 50;
  const spVal = document.createElement('span'); spVal.className = 'val'; spVal.textContent = spIn.value;
  spRow.appendChild(spIn); spRow.appendChild(spVal);
  wrap.appendChild(spRow);

  const zoneRow = document.createElement('div'); zoneRow.className = 'row zone-row';
  zoneRow.innerHTML = '<label>zone</label>';
  const zoneSel = document.createElement('select');
  const zAll = document.createElement('option'); zAll.value = ''; zAll.textContent = '(whole device)';
  zoneSel.appendChild(zAll);
  if (sel !== 'all' && sample && sample.zones && sample.zones.length) {{
    sample.zones.forEach((z, i) => {{
      const o = document.createElement('option'); o.value = String(i);
      o.textContent = i + ': ' + z; zoneSel.appendChild(o);
    }});
  }} else {{
    zoneRow.classList.add('hidden');
  }}
  zoneRow.appendChild(zoneSel);
  wrap.appendChild(zoneRow);

  const updateRelevance = () => {{
    const m = modeSel.value;
    spRow.classList.toggle('hidden', !NEEDS_SPEED(m));
    colorRow.classList.toggle('hidden', !NEEDS_COLOR(m));
  }};
  updateRelevance();

  const deb = new Debouncer(380);
  const fire = () => deb.run(async (signal) => {{
    const payload = {{
      class: cls,
      device: sel === 'all' ? '' : String(sel),
      mode: modeSel.value,
      color: NEEDS_COLOR(modeSel.value) ? colorIn.value.replace('#', '') : '',
      brightness: briIn.value,
      speed: NEEDS_SPEED(modeSel.value) ? spIn.value : '',
      zone: zoneSel.value,
    }};
    toast('→ ' + cls + ' · ' + payload.mode, '');
    const r = await fetch('/api/apply', {{
      method: 'POST',
      headers: {{ 'content-type': 'application/json' }},
      body: JSON.stringify(payload),
      signal,
    }});
    const t = await r.text();
    toast((r.ok ? '✓ ' : '✗ ') + cls + ' · ' + payload.mode + (r.ok ? '' : '\\n' + t.slice(0, 240)),
          r.ok ? 'ok' : 'err');
    if (r.ok) await refreshState({{ skipDevices: true }});
  }});

  modeSel.addEventListener('change', () => {{ updateRelevance(); fire(); }});
  colorIn.addEventListener('input', fire);
  briIn.addEventListener('input', () => {{ briVal.textContent = briIn.value; fire(); }});
  spIn.addEventListener('input', () => {{ spVal.textContent = spIn.value; fire(); }});
  zoneSel.addEventListener('change', fire);

  return wrap;
}}

function selectDevice(cls, idx) {{
  state.selectedByClass[cls] = idx;
  renderClasses();
}}

async function refreshState(opts) {{
  opts = opts || {{}};
  const r = await api('/api/state-full');
  if (!r.ok) {{ toast('state fetch failed', 'err'); return; }}
  state.override = !!r.body.override;
  state.lastByClass = r.body.last || {{}};
  if (!opts.skipDevices) {{
    state.devicesByClass = r.body.devices || {{}};
  }}
  renderTakeover();
  renderClasses();
}}

async function toggleOverride() {{
  const next = !state.override;
  toast('→ ' + (next ? 'pausing' : 'resuming') + ' keyledsd ...', '');
  const r = await fetch('/api/override', {{
    method: 'POST',
    headers: {{ 'content-type': 'application/json' }},
    body: JSON.stringify({{ enabled: next }}),
  }});
  const t = await r.text();
  toast((r.ok ? '✓ ' : '✗ ') + (next ? 'takeover ON' : 'takeover OFF')
        + (r.ok ? '' : '\\n' + t.slice(0, 200)), r.ok ? 'ok' : 'err');
  await refreshState();
}}

async function panicRestore() {{
  toast('→ restoring keyleds ...', '');
  const r = await fetch('/api/recover', {{ method: 'POST' }});
  const t = await r.text();
  toast((r.ok ? '✓ ' : '✗ ') + 'keyleds restored'
        + (r.ok ? '' : '\\n' + t.slice(0, 200)), r.ok ? 'ok' : 'err');
  await refreshState();
}}

function buildSceneItems(scene) {{
  const items = [];
  for (const [cls, meta] of Object.entries(CLASSES)) {{
    if (meta.hid && !state.override) continue;
    const devs = state.devicesByClass[cls] || [];
    if (!devs.length) continue;
    for (const d of devs) {{
      const preferred = scene.modes || [scene.mode];
      const mode = pickMode(d.modes, preferred, scene.fallback || []);
      if (!mode) continue;
      const wantColor = scene.color && !scene.noColor && NEEDS_COLOR(mode);
      items.push({{
        class: cls,
        device: String(d.index),
        mode,
        color: wantColor ? scene.color.replace('#', '') : '',
        brightness: 100,
        speed: NEEDS_SPEED(mode) ? 50 : '',
        zone: '',
      }});
    }}
  }}
  return items;
}}

async function runScene(scene) {{
  const items = buildSceneItems(scene);
  if (!items.length) {{
    toast('nothing to apply (takeover off?)', 'err');
    return;
  }}
  toast('→ scene: ' + scene.label, '');
  const r = await fetch('/api/apply-bulk', {{
    method: 'POST',
    headers: {{ 'content-type': 'application/json' }},
    body: JSON.stringify({{ items }}),
  }});
  const t = await r.text();
  toast((r.ok ? '✓ ' : '✗ ') + scene.label + '\\n' + t.slice(0, 240), r.ok ? 'ok' : 'err');
  await refreshState({{ skipDevices: true }});
}}

async function paintEverything() {{
  const c = $('#scene-color').value;
  await runScene({{ id: 'custom', label: 'paint ' + c, mode: 'Static', color: c, fallback: ['Direct'] }});
}}

document.getElementById('panic').addEventListener('click', panicRestore);
document.getElementById('override').addEventListener('click', toggleOverride);
document.getElementById('apply-color-all').addEventListener('click', paintEverything);

renderSceneButtons();
refreshState();
setInterval(() => refreshState({{ skipDevices: true }}), 18000);

</script>
</body></html>"""


# ------------------------------------------------------------------- api

async def api_state(_: web.Request) -> web.Response:
    return web.json_response(load_state())


async def api_state_full(_: web.Request) -> web.Response:
    state = load_state()
    devices: dict[str, list[dict[str, Any]]] = {}
    for cls in DEVICE_CLASSES:
        devices[cls] = await devices_for_class(cls)
    return web.json_response({
        "override": bool(state.get("override")),
        "last": state.get("last", {}),
        "devices": devices,
    })


async def api_devices(request: web.Request) -> web.Response:
    cls = request.match_info["cls"]
    if cls not in DEVICE_CLASSES:
        return web.json_response({"error": f"unknown class: {cls}"}, status=404)
    state = load_state()
    devs = await devices_for_class(cls)
    return web.json_response({"devices": devs, "override": bool(state.get("override"))})


async def api_apply(request: web.Request) -> web.Response:
    payload = await request.json()
    status, body = await apply_settings(payload)
    return web.Response(text=body, status=status)


async def api_apply_bulk(request: web.Request) -> web.Response:
    payload = await request.json()
    status, body = await apply_bulk(payload)
    return web.Response(text=body, status=status)


async def api_override(request: web.Request) -> web.Response:
    payload = await request.json()
    enabled = bool(payload.get("enabled"))
    msg = await set_override(enabled)
    return web.Response(text=msg)


async def api_recover(_: web.Request) -> web.Response:
    msg = await set_override(False)
    return web.Response(text=msg)


async def page_index(_: web.Request) -> web.Response:
    return web.Response(text=_index_html(), content_type="text/html")


async def page_device_redirect(_: web.Request) -> web.Response:
    raise web.HTTPFound("/")


def main() -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    app = web.Application()
    app.on_startup.append(startup_recovery)
    app.on_shutdown.append(shutdown_cleanup)
    app.add_routes([
        web.get("/", page_index),
        web.get("/d/{cls}", page_device_redirect),
        web.get("/api/state", api_state),
        web.get("/api/state-full", api_state_full),
        web.get("/api/devices/{cls}", api_devices),
        web.post("/api/apply", api_apply),
        web.post("/api/apply-bulk", api_apply_bulk),
        web.post("/api/override", api_override),
        web.post("/api/recover", api_recover),
    ])
    web.run_app(
        app,
        host=os.environ.get("RGB_HOST", "0.0.0.0"),
        port=int(os.environ.get("RGB_PORT", "6681")),
    )


if __name__ == "__main__":
    main()
