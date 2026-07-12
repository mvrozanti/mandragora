#!/usr/bin/env python3
"""rgb-control — single-page RGB web UI for Mandragora (v2).

Architecture:
  - RAM + motherboard go through the long-running openrgb SDK server on :6742
    (shared with wal-to-rgb-daemon). Writes serialize on /tmp/openrgb-write.lock
    so daemon and UI never collide on SMBus.
  - Mouse + keyboard are HID devices that conflict with keyledsd. They are gated
    behind the "takeover" toggle and use short-lived openrgb CLI calls against a
    separate HID_CONFIG dir.

UI v2:
  - Single page, every class panel visible at once (no drill-in).
  - Quick scenes (off / white / primaries / rainbow / breathing), applied via
    /api/scene → fans out across all detected devices.
  - Saved presets: snapshot of state["last"] under a user-given name; click to
    re-apply across every class.
  - Undo / Redo: every apply (single, bulk, scene, preset) pushes a history
    entry; arrows in the header walk the history pointer.
  - Takeover toggle visible with plain-language copy.

Recovery is layered: panic button restores keyledsd; takeover-off restarts
keyledsd idempotently; ExecStopPost restarts keyledsd if the service dies;
startup forces takeover=false.
"""
from __future__ import annotations

import asyncio
import fcntl
import json
import logging
import os
import re
import shutil
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Any

from aiohttp import web
from openrgb import OpenRGBClient
from openrgb.utils import DeviceType, RGBColor

log = logging.getLogger("rgb-control")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")

OPENRGB = shutil.which("openrgb") or "openrgb"
SYSTEMCTL = shutil.which("systemctl") or "/run/current-system/sw/bin/systemctl"

OPENRGB_HOST = os.environ.get("OPENRGB_SERVER_HOST", "127.0.0.1")
OPENRGB_PORT = int(os.environ.get("OPENRGB_SERVER_PORT", "6742"))
WRITE_LOCK = "/tmp/openrgb-write.lock"
PAUSE_SENTINEL = Path(os.environ.get("XDG_RUNTIME_DIR", "/run/user/1000")) / "rgb-control-paused"

STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state")) / "rgb-control"
STATE_FILE = STATE_DIR / "state.json"
LEGACY_STATE_FILE = Path("/persistent/mandragora/.local/share/rgb-control/state.json")


def migrate_state() -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    if not STATE_FILE.exists() and LEGACY_STATE_FILE.exists():
        shutil.copy2(LEGACY_STATE_FILE, STATE_FILE)
        log.info("migrated rgb-control state from %s to %s", LEGACY_STATE_FILE, STATE_FILE)

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
    "ram":      {"type": "DRAM",        "label": "RAM",         "hid": False, "sdk_type": DeviceType.DRAM},
    "mobo":     {"type": "Motherboard", "label": "Motherboard", "hid": False, "sdk_type": DeviceType.MOTHERBOARD},
    "mouse":    {"type": "Mouse",       "label": "Mouse",       "hid": True,  "sdk_type": None},
    "keyboard": {"type": "Keyboard",    "label": "Keyboard",    "hid": True,  "sdk_type": None},
}

ENUM_TTL_S = 8.0
HISTORY_LIMIT = 50


@contextmanager
def write_lock(timeout: float = 2.0):
    fd = os.open(WRITE_LOCK, os.O_CREAT | os.O_WRONLY, 0o666)
    try:
        deadline = time.monotonic() + timeout
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise TimeoutError(f"openrgb-write.lock held >{timeout}s")
                time.sleep(0.01)
        yield
    finally:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)


def touch_pause():
    try:
        PAUSE_SENTINEL.parent.mkdir(parents=True, exist_ok=True)
    except Exception:
        pass
    PAUSE_SENTINEL.touch()


def clear_pause():
    try:
        PAUSE_SENTINEL.unlink()
    except FileNotFoundError:
        pass


# -------------------------------------------------------------- state schema

def load_state() -> dict[str, Any]:
    try:
        s = json.loads(STATE_FILE.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        s = {}
    s.setdefault("override", False)
    last = s.setdefault("last", {})
    for k in DEVICE_CLASSES:
        last.setdefault(k, {})
    s.setdefault("history", [])
    s.setdefault("history_ptr", -1)
    s.setdefault("presets", {})
    return s


def save_state(state: dict[str, Any]) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state))


def _clone_snapshot(last: dict[str, Any]) -> dict[str, Any]:
    return json.loads(json.dumps(last))


def push_history(label: str) -> None:
    state = load_state()
    ptr = state["history_ptr"]
    if ptr < len(state["history"]) - 1:
        state["history"] = state["history"][: ptr + 1]
    snapshot = _clone_snapshot(state["last"])
    state["history"].append({"ts": int(time.time()), "label": label, "last": snapshot})
    if len(state["history"]) > HISTORY_LIMIT:
        drop = len(state["history"]) - HISTORY_LIMIT
        state["history"] = state["history"][drop:]
    state["history_ptr"] = len(state["history"]) - 1
    save_state(state)


def record_apply(cls: str, idx: int, payload: dict[str, Any]) -> None:
    state = load_state()
    state["last"].setdefault(cls, {})[str(idx)] = {
        "mode": payload.get("mode"),
        "color": payload.get("color"),
        "brightness": payload.get("brightness"),
        "speed": payload.get("speed"),
        "zone": payload.get("zone"),
        "ts": int(time.time()),
    }
    save_state(state)


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


_sdk_client: OpenRGBClient | None = None


def _sdk() -> OpenRGBClient:
    global _sdk_client
    if _sdk_client is None:
        _sdk_client = OpenRGBClient(address=OPENRGB_HOST, port=OPENRGB_PORT, name="rgb-control")
    return _sdk_client


def _sdk_reset():
    global _sdk_client
    if _sdk_client is not None:
        try:
            _sdk_client.disconnect()
        except Exception:
            pass
    _sdk_client = None


def _sdk_device_dict(dev: Any, all_devices: list[Any]) -> dict[str, Any]:
    return {
        "index": all_devices.index(dev),
        "name": dev.name,
        "type": str(dev.type).rsplit(".", 1)[-1],
        "modes": [m.name for m in dev.modes],
        "zones": [z.name for z in dev.zones],
    }


def config_dir_for_class(cls: str) -> Path:
    return HID_CONFIG if DEVICE_CLASSES[cls]["hid"] else SAFE_CONFIG


_enum_cache: dict[str, tuple[float, list[dict[str, Any]]]] = {}


async def list_devices_cli(config_dir: Path) -> list[dict[str, Any]]:
    key = str(config_dir)
    now = time.monotonic()
    cached = _enum_cache.get(key)
    if cached and now - cached[0] < ENUM_TTL_S:
        return cached[1]
    proc = await asyncio.create_subprocess_exec(
        OPENRGB, "--config", str(config_dir), "--noautoconnect", "--list-devices",
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
    )
    out, err = await proc.communicate()
    if proc.returncode != 0:
        log.warning("openrgb list-devices failed (rc=%s): %s", proc.returncode, err.decode(errors="replace"))
        return []
    devices = parse_list_devices(out.decode(errors="replace"))
    _enum_cache[key] = (now, devices)
    return devices


_quoted_or_bare = re.compile(r"'([^']*)'|(\S+)")


def _split_modes_or_zones(line: str) -> list[str]:
    items = []
    for q, b in _quoted_or_bare.findall(line):
        token = q if q else b
        if token.startswith("[") and token.endswith("]"):
            token = token[1:-1]
        items.append(token)
    return items


def parse_list_devices(text: str) -> list[dict[str, Any]]:
    devices: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None
    header = re.compile(r"^(\d+):\s+(.*)$")
    for raw in text.splitlines():
        line = raw.rstrip()
        if not line:
            if current is not None:
                devices.append(current)
                current = None
            continue
        m = header.match(line)
        if m:
            if current is not None:
                devices.append(current)
            current = {
                "index": int(m.group(1)),
                "name": m.group(2).strip(),
                "type": None,
                "modes": [],
                "zones": [],
            }
            continue
        if current is None:
            continue
        stripped = line.strip()
        if stripped.startswith("Type:"):
            current["type"] = stripped.split(":", 1)[1].strip()
        elif stripped.startswith("Modes:"):
            current["modes"] = _split_modes_or_zones(stripped.split(":", 1)[1].strip())
        elif stripped.startswith("Zones:"):
            current["zones"] = _split_modes_or_zones(stripped.split(":", 1)[1].strip())
    if current is not None:
        devices.append(current)
    return devices


async def devices_for_class(cls: str) -> list[dict[str, Any]]:
    info = DEVICE_CLASSES[cls]
    if info["hid"]:
        if not load_state().get("override"):
            return []
        all_devs = await list_devices_cli(config_dir_for_class(cls))
        return [d for d in all_devs if (d.get("type") or "").lower() == info["type"].lower()]
    return await asyncio.to_thread(_sdk_devices_for_class, cls)


def _sdk_devices_for_class(cls: str) -> list[dict[str, Any]]:
    info = DEVICE_CLASSES[cls]
    try:
        c = _sdk()
        c.update()
        out = []
        for d in c.devices:
            if d.type == info["sdk_type"]:
                out.append(_sdk_device_dict(d, c.devices))
        return out
    except Exception as e:
        log.warning("sdk devices_for_class(%s) failed: %s", cls, e)
        _sdk_reset()
        return []


_HEX_COLOR = re.compile(r"^[0-9A-Fa-f]{6}$")


def _normalize_color(c: str | None) -> str | None:
    if c is None:
        return None
    c = c.strip().lstrip("#")
    if not _HEX_COLOR.match(c):
        return None
    return c.upper()


def _color_to_rgb(hex_color: str) -> RGBColor:
    return RGBColor(int(hex_color[0:2], 16), int(hex_color[2:4], 16), int(hex_color[4:6], 16))


_I2C_NOISE = re.compile(r"^\[i2c_smbus_linux\] Failed to read i2c device PCI device ID\s*$")


def _clean_openrgb_output(text: str) -> str:
    lines = [ln for ln in text.splitlines() if not _I2C_NOISE.match(ln)]
    return "\n".join(lines).strip()


def _sdk_apply_one(cls: str, device_idx: int, mode: str, color: str | None,
                   zone: str | int | None) -> tuple[int, str]:
    try:
        with write_lock(timeout=2.0):
            c = _sdk()
            c.update()
            if device_idx < 0 or device_idx >= len(c.devices):
                return 404, f"device index {device_idx} out of range (have {len(c.devices)})"
            dev = c.devices[device_idx]
            try:
                dev.set_mode(mode)
            except Exception as e:
                return 500, f"set_mode({mode!r}) failed: {e}"
            if color is not None:
                rgb = _color_to_rgb(color)
                if zone is None or zone == "":
                    dev.set_color(rgb)
                else:
                    try:
                        z_idx = int(zone)
                    except ValueError:
                        return 400, f"zone must be an integer, got {zone!r}"
                    if z_idx < 0 or z_idx >= len(dev.zones):
                        return 404, f"zone index {z_idx} out of range"
                    z = dev.zones[z_idx]
                    z.set_colors([rgb] * len(z.leds))
                    dev.show()
        touch_pause()
        return 200, f"ok: device {device_idx} ({dev.name}) → mode={mode} color={color or '-'}"
    except TimeoutError as e:
        return 503, f"openrgb write lock busy: {e}"
    except Exception as e:
        log.warning("sdk apply failed: %s", e)
        _sdk_reset()
        return 500, f"sdk apply error: {e}"


async def _apply_one_cli(cls: str, device_idx: int, mode: str, color: str | None,
                         zone: str | int | None, speed: str | int | None,
                         brightness: str | int | None) -> tuple[int, str]:
    args = [OPENRGB, "--config", str(config_dir_for_class(cls)), "--noautoconnect",
            "--device", str(device_idx)]
    if zone is not None and zone != "":
        args += ["--zone", str(int(zone))]
    args += ["--mode", mode]
    if color is not None:
        args += ["--color", color]
    if speed is not None and speed != "":
        args += ["--speed", str(int(speed))]
    if brightness is not None and brightness != "":
        args += ["--brightness", str(int(brightness))]
    log.info("apply-cli: %s", " ".join(args[1:]))
    proc = await asyncio.create_subprocess_exec(
        *args, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT,
    )
    out, _ = await proc.communicate()
    return proc.returncode, _clean_openrgb_output(out.decode(errors="replace"))


async def _apply_one(cls: str, idx: int, payload: dict[str, Any]) -> tuple[int, str]:
    info = DEVICE_CLASSES[cls]
    mode = (payload.get("mode") or "").strip()
    if not mode:
        return 400, "missing mode"
    color = _normalize_color(payload.get("color"))
    zone = payload.get("zone")
    speed = payload.get("speed")
    brightness = payload.get("brightness")
    if info["hid"]:
        rc, body = await _apply_one_cli(cls, idx, mode, color, zone, speed, brightness)
    else:
        rc, body = await asyncio.to_thread(_sdk_apply_one, cls, idx, mode, color, zone)
    rc = 200 if rc in (200, 0) else rc
    if rc == 200:
        record_apply(cls, idx, {"mode": mode, "color": color, "zone": zone, "speed": speed, "brightness": brightness})
    return rc, body


async def apply_settings(payload: dict[str, Any], history_label: str | None = None) -> tuple[int, str]:
    cls = payload.get("class")
    if cls not in DEVICE_CLASSES:
        return 400, f"unknown class: {cls}"
    info = DEVICE_CLASSES[cls]
    if info["hid"] and not load_state().get("override"):
        return 409, "takeover is off — enable it to control mouse/keyboard"
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

    results = []
    overall_rc = 200
    for idx in targets:
        rc, body = await _apply_one(cls, idx, payload)
        results.append(f"[device {idx}] rc={rc} {body}".rstrip())
        if rc != 200:
            overall_rc = rc if overall_rc == 200 else overall_rc
    _enum_cache.clear()
    if overall_rc == 200 and history_label is not None:
        push_history(history_label)
    return overall_rc, "\n".join(results)[-1200:]


async def apply_bulk(items: list[dict[str, Any]], history_label: str) -> tuple[int, str]:
    if not items:
        return 400, "no items"
    override = bool(load_state().get("override"))
    runnable: list[dict[str, Any]] = []
    skipped: list[str] = []
    for item in items:
        cls = item.get("class")
        if cls not in DEVICE_CLASSES:
            skipped.append(f"{cls}: unknown class")
            continue
        if DEVICE_CLASSES[cls]["hid"] and not override:
            skipped.append(f"{cls}: takeover off")
            continue
        runnable.append(item)
    if not runnable:
        return 409, "nothing applied (takeover off?)\n" + "\n".join(skipped)
    summary = []
    overall = 200
    for item in runnable:
        rc, body = await apply_settings(item, history_label=None)
        summary.append(f"{item.get('class')}: rc={rc}")
        if rc != 200:
            overall = rc if overall == 200 else overall
    if overall == 200:
        push_history(history_label)
    if skipped:
        summary += [f"skipped {s}" for s in skipped]
    return overall, "\n".join(summary)


SCENE_SPECS = {
    "off":       {"mode": "Off",       "color": None,     "fallback_modes": ["Direct", "Static"]},
    "white":     {"mode": "Static",    "color": "FFFFFF"},
    "red":       {"mode": "Static",    "color": "FF2233"},
    "amber":     {"mode": "Static",    "color": "FFAA22"},
    "green":     {"mode": "Static",    "color": "00FF66"},
    "cyan":      {"mode": "Static",    "color": "22CCFF"},
    "blue":      {"mode": "Static",    "color": "3366FF"},
    "magenta":   {"mode": "Static",    "color": "FF33AA"},
    "rainbow":   {"mode_pool": ["Rainbow Wave", "Spectrum Cycle", "Rainbow", "Cycle"],
                  "color": None, "fallback_modes": ["Static"]},
    "breathing": {"mode_pool": ["Breathing", "Pulse", "Pulsing"],
                  "color": None, "fallback_modes": ["Static"]},
}


def _pick_mode(device_modes: list[str], preferred: list[str], fallback: list[str]) -> str | None:
    lower = [m.lower() for m in device_modes]
    for cand in preferred + fallback:
        if not cand:
            continue
        ci = cand.lower()
        if ci in lower:
            return device_modes[lower.index(ci)]
    return device_modes[0] if device_modes else None


async def build_scene_items(scene_id: str, override_color: str | None = None) -> list[dict[str, Any]]:
    spec = SCENE_SPECS.get(scene_id)
    if spec is None:
        return []
    items: list[dict[str, Any]] = []
    override = bool(load_state().get("override"))
    for cls, info in DEVICE_CLASSES.items():
        if info["hid"] and not override:
            continue
        devs = await devices_for_class(cls)
        if not devs:
            continue
        preferred = spec.get("mode_pool") or [spec["mode"]]
        fallback = spec.get("fallback_modes", [])
        for d in devs:
            mode = _pick_mode(d.get("modes") or [], preferred, fallback)
            if not mode:
                continue
            color = override_color if override_color is not None else spec.get("color")
            items.append({
                "class": cls,
                "device": str(d["index"]),
                "mode": mode,
                "color": color,
                "brightness": 100,
                "speed": 50 if any(k in mode.lower() for k in ("wave", "cycle", "breath", "pulse", "rainbow", "spectrum")) else "",
                "zone": "",
            })
    return items


async def apply_scene(scene_id: str, override_color: str | None = None) -> tuple[int, str]:
    if scene_id == "custom" and override_color:
        spec = {"mode": "Static", "color": override_color, "fallback_modes": ["Direct"]}
        SCENE_SPECS["custom"] = spec
    items = await build_scene_items(scene_id, override_color=override_color)
    if not items:
        return 409, f"nothing to apply for scene {scene_id!r} (takeover off?)"
    label = f"scene: {scene_id}" + (f" {override_color}" if override_color and scene_id == "custom" else "")
    return await apply_bulk(items, label)


# -------------------------------------------------------------- undo / redo

async def history_step(direction: int) -> tuple[int, str]:
    state = load_state()
    hist = state["history"]
    ptr = state["history_ptr"]
    target = ptr + direction
    if target < 0 or target >= len(hist):
        return 409, "at history boundary"
    snapshot = hist[target]
    items = []
    for cls, devs in snapshot.get("last", {}).items():
        if cls not in DEVICE_CLASSES:
            continue
        for idx_str, settings in devs.items():
            mode = settings.get("mode")
            if not mode:
                continue
            items.append({
                "class": cls,
                "device": idx_str,
                "mode": mode,
                "color": settings.get("color"),
                "brightness": settings.get("brightness", ""),
                "speed": settings.get("speed", ""),
                "zone": settings.get("zone", ""),
            })
    override = bool(state.get("override"))
    runnable = [i for i in items if not (DEVICE_CLASSES[i["class"]]["hid"] and not override)]
    overall = 200
    for item in runnable:
        rc, _ = await apply_settings(item, history_label=None)
        if rc != 200 and overall == 200:
            overall = rc
    if overall == 200:
        state2 = load_state()
        state2["history_ptr"] = target
        state2["last"] = _clone_snapshot(snapshot["last"])
        save_state(state2)
    label = snapshot.get("label") or "—"
    direction_word = "undo" if direction < 0 else "redo"
    return overall, f"{direction_word} → {label}"


# -------------------------------------------------------------- presets

async def preset_save(name: str) -> tuple[int, str]:
    name = (name or "").strip()
    if not name:
        return 400, "preset needs a name"
    state = load_state()
    state["presets"][name] = {
        "ts": int(time.time()),
        "last": _clone_snapshot(state["last"]),
    }
    save_state(state)
    return 200, f"saved preset {name!r}"


async def preset_delete(name: str) -> tuple[int, str]:
    state = load_state()
    if name not in state["presets"]:
        return 404, f"preset {name!r} not found"
    del state["presets"][name]
    save_state(state)
    return 200, f"deleted preset {name!r}"


async def preset_apply(name: str) -> tuple[int, str]:
    state = load_state()
    preset = state["presets"].get(name)
    if preset is None:
        return 404, f"preset {name!r} not found"
    snapshot = preset.get("last", {})
    items = []
    for cls, devs in snapshot.items():
        if cls not in DEVICE_CLASSES:
            continue
        for idx_str, settings in devs.items():
            mode = settings.get("mode")
            if not mode:
                continue
            items.append({
                "class": cls,
                "device": idx_str,
                "mode": mode,
                "color": settings.get("color"),
                "brightness": settings.get("brightness", ""),
                "speed": settings.get("speed", ""),
                "zone": settings.get("zone", ""),
            })
    if not items:
        return 409, f"preset {name!r} is empty"
    return await apply_bulk(items, history_label=f"preset: {name}")


# -------------------------------------------------------------- other

async def revert_to_animation() -> str:
    clear_pause()
    return "animation resumed"


async def set_override(enabled: bool) -> str:
    state = load_state()
    state["override"] = bool(enabled)
    save_state(state)
    _enum_cache.clear()
    if enabled:
        return await stop_keyleds()
    return await restart_keyleds()


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
    clear_pause()


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
button { font: inherit; cursor: pointer; }

.wrap { max-width: 1100px; margin: 0 auto; display: flex; flex-direction: column; gap: 1.1rem; }

header.top { display: flex; justify-content: space-between; align-items: center;
  gap: 1rem; flex-wrap: wrap; padding-bottom: 1rem; border-bottom: 1px solid var(--line); }
.title { display: flex; align-items: center; gap: 0.9rem; flex-wrap: wrap; }
.title h1 { font-size: 1.45rem; font-weight: 600; letter-spacing: 0.04em; color: var(--accent); }
.title h1::before { content: "$ "; color: var(--dim); font-weight: 400; }
.title .sub { color: var(--dim); font-size: 0.72rem; letter-spacing: 0.22em;
  text-transform: uppercase; }
.history { display: flex; gap: 0.4rem; align-items: center; padding-left: 0.6rem;
  border-left: 1px solid var(--line); }
.history button { background: var(--panel-2); color: var(--fg); border: 1px solid var(--line);
  padding: 0.35rem 0.6rem; font-size: 1rem; line-height: 1; }
.history button:hover:not(:disabled) { border-color: var(--accent); color: var(--accent); }
.history button:disabled { opacity: 0.35; cursor: not-allowed; }
.history .label { color: var(--dim); font-size: 0.72rem; max-width: 220px;
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }

.head-actions { display: flex; gap: 0.5rem; flex-wrap: wrap; }
.head-actions button { background: transparent; color: var(--fg); border: 1px solid var(--line);
  padding: 0.5rem 0.9rem; text-transform: lowercase; letter-spacing: 0.05em; transition: 0.12s; }
.head-actions button:hover { border-color: var(--accent); color: var(--accent); }
.head-actions .panic { color: var(--warn); border-color: var(--warn); }
.head-actions .panic:hover { background: var(--warn); color: var(--bg); }

section.card { background: var(--panel); border: 1px solid var(--line); padding: 1rem 1.1rem; }
section.card > h2 { font-size: 0.72rem; letter-spacing: 0.22em; text-transform: uppercase;
  color: var(--dim); margin-bottom: 0.85rem; font-weight: 500; display: flex; align-items: center;
  gap: 0.6rem; }
section.card > h2 small { color: var(--dim); font-size: 0.7rem; letter-spacing: 0; text-transform: none; }

/* quick scenes */
.scenes .scene-buttons { display: flex; flex-wrap: wrap; gap: 0.5rem; }
.scene-btn { background: var(--panel-2); color: var(--fg); border: 1px solid var(--line);
  padding: 0.55rem 0.9rem; transition: 0.12s; display: inline-flex; gap: 0.5rem;
  align-items: center; letter-spacing: 0.02em; }
.scene-btn:hover { border-color: var(--accent); background: var(--hover); color: var(--accent); }
.scene-btn .swatch { width: 14px; height: 14px; border: 1px solid rgba(255,255,255,0.18);
  flex: 0 0 14px; border-radius: 2px; }
.scenes .scene-color { display: flex; gap: 0.6rem; align-items: center; padding-top: 0.9rem;
  margin-top: 0.85rem; border-top: 1px dashed var(--line); flex-wrap: wrap; }
.scenes .scene-color label { color: var(--dim); font-size: 0.72rem; letter-spacing: 0.1em;
  text-transform: uppercase; }
.scenes input[type=color] { width: 72px; height: 36px; background: var(--panel-2);
  border: 1px solid var(--line); padding: 0; cursor: pointer; }
.scenes .apply-all { background: var(--accent); color: var(--bg); border: 1px solid var(--accent);
  padding: 0.6rem 1.1rem; font-weight: 600; letter-spacing: 0.04em; }
.scenes .apply-all:hover { filter: brightness(1.12); }

/* presets */
.presets .preset-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
  gap: 0.55rem; margin-bottom: 0.85rem; }
.preset-tile { background: var(--panel-2); border: 1px solid var(--line); padding: 0.65rem 0.6rem;
  color: var(--fg); text-align: left; display: flex; flex-direction: column; gap: 0.4rem;
  transition: 0.1s; position: relative; }
.preset-tile:hover { border-color: var(--accent); background: var(--hover); }
.preset-tile .swatches { display: flex; gap: 2px; height: 16px; border: 1px solid rgba(255,255,255,0.06); }
.preset-tile .swatches span { flex: 1; background: #222; }
.preset-tile .name { font-size: 0.85rem; color: var(--fg); white-space: nowrap;
  overflow: hidden; text-overflow: ellipsis; }
.preset-tile .meta { font-size: 0.68rem; color: var(--dim); }
.preset-tile .del { position: absolute; top: 4px; right: 4px; background: transparent;
  border: 1px solid var(--line); color: var(--dim); width: 18px; height: 18px;
  font-size: 0.7rem; line-height: 1; display: none; padding: 0; }
.preset-tile:hover .del { display: block; }
.preset-tile .del:hover { border-color: var(--warn); color: var(--warn); }
.presets .save-btn { background: var(--panel-2); color: var(--fg); border: 1px dashed var(--line);
  padding: 0.55rem 1rem; letter-spacing: 0.05em; }
.presets .save-btn:hover { border-color: var(--accent); color: var(--accent); }
.presets .empty { color: var(--dim); font-size: 0.82rem; padding: 0.5rem 0 0.85rem; }

/* takeover */
.takeover { display: flex; justify-content: space-between; align-items: center;
  gap: 1rem; flex-wrap: wrap; transition: 0.12s; }
.takeover-info strong { color: var(--fg); font-size: 0.95rem; display: block; margin-bottom: 0.3rem; }
.takeover-info p { color: var(--dim); font-size: 0.8rem; max-width: 640px; line-height: 1.5; }
.takeover-info p em { color: var(--warn); font-style: normal; }
.takeover .switch { background: var(--panel-2); color: var(--fg); border: 1px solid var(--line);
  padding: 0.7rem 1.4rem; letter-spacing: 0.08em;
  text-transform: uppercase; font-size: 0.74rem; min-width: 140px; }
.takeover .switch:hover { border-color: var(--accent); }
.takeover.on { border-color: var(--warm);
  background: linear-gradient(180deg, rgba(255,179,71,0.06), var(--panel)); }
.takeover.on .takeover-info strong { color: var(--warm); }
.takeover.on .switch { background: var(--warm); color: var(--bg); border-color: var(--warm); }

/* class panels */
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

.locked-msg, .empty-msg { font-size: 0.82rem; padding: 0.75rem 0.9rem; }
.locked-msg { color: var(--warm); border: 1px dashed var(--warm); background: rgba(255,179,71,0.06); }
.empty-msg { color: var(--dim); border: 1px dashed var(--line); background: var(--panel-2); }

.device-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(130px, 1fr));
  gap: 0.55rem; margin-bottom: 0.95rem; }
.dev-tile { background: var(--panel-2); border: 1px solid var(--line); padding: 0.7rem 0.6rem;
  color: var(--fg); text-align: left; display: flex; flex-direction: column; gap: 0.4rem;
  transition: 0.1s; overflow: hidden; }
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
  padding: 0.4rem 0.55rem; flex: 1; min-width: 0;
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

#modal { position: fixed; inset: 0; background: rgba(0,0,0,0.6); display: none;
  align-items: center; justify-content: center; z-index: 20; }
#modal.show { display: flex; }
#modal .box { background: var(--panel); border: 1px solid var(--accent); padding: 1.2rem 1.4rem;
  min-width: 320px; max-width: 90vw; }
#modal h3 { color: var(--accent); font-size: 0.95rem; margin-bottom: 0.7rem; }
#modal input { width: 100%; background: var(--panel-2); border: 1px solid var(--line);
  color: var(--fg); padding: 0.5rem; font: inherit; margin-bottom: 0.8rem; }
#modal .actions { display: flex; gap: 0.5rem; justify-content: flex-end; }
#modal button { background: var(--panel-2); color: var(--fg); border: 1px solid var(--line);
  padding: 0.45rem 0.9rem; }
#modal button.primary { background: var(--accent); color: var(--bg); border-color: var(--accent); }

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
    <div class="history">
      <button id="undo" title="undo">←</button>
      <button id="redo" title="redo">→</button>
      <span class="label" id="history-label">—</span>
    </div>
  </div>
  <div class="head-actions">
    <button id="resume">resume animation</button>
    <button id="panic" class="panic">restore keyleds</button>
  </div>
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

<section class="card presets">
  <h2>saved presets</h2>
  <div class="preset-grid" id="preset-grid"></div>
  <button class="save-btn" id="save-preset">+ save current state as preset</button>
</section>

<section class="card takeover" id="takeover">
  <div class="takeover-info">
    <strong id="takeover-title">keyboard + mouse</strong>
    <p>OFF: per-key keyledsd effects run normally. ON: openrgb takes over the keyboard and mouse via HID, keyledsd is paused. Toggle back OFF (or hit <em>restore keyleds</em> top-right) to return to normal.</p>
  </div>
  <button class="switch" id="override">enable</button>
</section>

<div class="classes" id="classes"></div>

<footer class="foot">openrgb SDK · server on 127.0.0.1:6742 · GET <code>/api/state-full</code> · POST <code>/api/scene</code> / <code>/api/undo</code></footer>

</div>

<div id="modal"><div class="box">
  <h3 id="modal-title">save preset</h3>
  <input type="text" id="modal-input" placeholder="preset name">
  <div class="actions">
    <button id="modal-cancel">cancel</button>
    <button id="modal-ok" class="primary">save</button>
  </div>
</div></div>

<div id="toast"></div>

<script>
const CLASSES = {json.dumps(cls_meta)};
const SCENES = [
  {{ id: "off",       label: "off",       swatch: "#000000" }},
  {{ id: "white",     label: "white",     swatch: "#ffffff" }},
  {{ id: "red",       label: "red",       swatch: "#ff2233" }},
  {{ id: "amber",     label: "amber",     swatch: "#ffaa22" }},
  {{ id: "green",     label: "green",     swatch: "#00ff66" }},
  {{ id: "cyan",      label: "cyan",      swatch: "#22ccff" }},
  {{ id: "blue",      label: "blue",      swatch: "#3366ff" }},
  {{ id: "magenta",   label: "magenta",   swatch: "#ff33aa" }},
  {{ id: "rainbow",   label: "rainbow",   swatch: "linear-gradient(90deg,#f00,#ff0,#0f0,#0ff,#00f,#f0f)" }},
  {{ id: "breathing", label: "breathing", swatch: "#00ff88" }},
];
const ANIM_RE = /wave|cycle|breath|pulse|rainbow|spectrum|flash|blink|chase|fade|sweep|move|drip|rain/i;
const NEEDS_SPEED = (mode) => ANIM_RE.test(mode || "");
const NO_COLOR_RE = /^(off|spectrum|cycle|rainbow|random)/i;
const NEEDS_COLOR = (mode) => !NO_COLOR_RE.test(mode || "");

const $ = (s, r=document) => r.querySelector(s);

const state = {{
  override: false,
  devicesByClass: {{}},
  lastByClass: {{}},
  presets: {{}},
  history: [],
  historyPtr: -1,
  selectedByClass: {{}},
}};

function toast(msg, kind) {{
  const el = $('#toast');
  el.textContent = msg;
  el.className = 'show ' + (kind || '');
  clearTimeout(toast._t);
  toast._t = setTimeout(() => el.className = '', 2600);
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

function hexFromLast(c) {{ return c ? ('#' + c) : null; }}
function selectedIdx(cls) {{
  const sel = state.selectedByClass[cls];
  return (sel === undefined || sel === null) ? 'all' : sel;
}}
function shortName(s) {{ return s.length > 26 ? s.slice(0, 23) + '...' : s; }}
function escapeHtml(s) {{
  return s.replace(/[&<>"]/g, c => ({{ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;' }})[c]);
}}

// ---- header / history ----

function renderHistory() {{
  const undo = $('#undo'), redo = $('#redo'), lbl = $('#history-label');
  undo.disabled = state.historyPtr <= 0;
  redo.disabled = state.historyPtr >= state.history.length - 1;
  const cur = state.history[state.historyPtr];
  lbl.textContent = cur ? (cur.label || '—') : '—';
}}

async function doUndo() {{
  toast('→ undoing ...', '');
  const r = await fetch('/api/undo', {{ method: 'POST' }});
  const t = await r.text();
  toast((r.ok ? '✓ ' : '✗ ') + t.slice(0, 200), r.ok ? 'ok' : 'err');
  await refreshState();
}}
async function doRedo() {{
  toast('→ redoing ...', '');
  const r = await fetch('/api/redo', {{ method: 'POST' }});
  const t = await r.text();
  toast((r.ok ? '✓ ' : '✗ ') + t.slice(0, 200), r.ok ? 'ok' : 'err');
  await refreshState();
}}

// ---- scenes ----

function renderSceneButtons() {{
  const row = $('#scene-buttons');
  row.innerHTML = '';
  for (const s of SCENES) {{
    const b = document.createElement('button');
    b.className = 'scene-btn';
    b.innerHTML = '<span class="swatch" style="background:' + s.swatch + '"></span>' + s.label;
    b.addEventListener('click', () => runScene(s.id));
    row.appendChild(b);
  }}
}}

async function runScene(sceneId, color) {{
  toast('→ scene: ' + sceneId, '');
  const r = await fetch('/api/scene', {{
    method: 'POST',
    headers: {{ 'content-type': 'application/json' }},
    body: JSON.stringify({{ scene: sceneId, color: color || null }}),
  }});
  const t = await r.text();
  toast((r.ok ? '✓ ' : '✗ ') + sceneId + (r.ok ? '' : '\\n' + t.slice(0, 200)), r.ok ? 'ok' : 'err');
  await refreshState();
}}

async function paintEverything() {{
  const c = $('#scene-color').value.replace('#', '').toUpperCase();
  await runScene('custom', c);
}}

// ---- presets ----

function renderPresets() {{
  const grid = $('#preset-grid');
  grid.innerHTML = '';
  const names = Object.keys(state.presets);
  if (names.length === 0) {{
    grid.innerHTML = '<div class="empty">no presets yet — paint things you like, then click save below</div>';
    return;
  }}
  for (const name of names.sort()) {{
    const p = state.presets[name];
    const tile = document.createElement('button');
    tile.className = 'preset-tile';
    tile.title = 'click to apply';
    const sw = document.createElement('div'); sw.className = 'swatches';
    const colors = collectPresetColors(p);
    for (const c of (colors.length ? colors : ['#222'])) {{
      const s = document.createElement('span'); s.style.background = c;
      sw.appendChild(s);
    }}
    tile.appendChild(sw);
    const n = document.createElement('div'); n.className = 'name';
    n.textContent = name;
    tile.appendChild(n);
    const meta = document.createElement('div'); meta.className = 'meta';
    const cnt = countPresetDevices(p);
    meta.textContent = cnt + ' device' + (cnt === 1 ? '' : 's');
    tile.appendChild(meta);
    const del = document.createElement('span'); del.className = 'del'; del.textContent = '×';
    del.addEventListener('click', (e) => {{ e.stopPropagation(); deletePreset(name); }});
    tile.appendChild(del);
    tile.addEventListener('click', () => applyPreset(name));
    grid.appendChild(tile);
  }}
}}

function collectPresetColors(preset) {{
  const out = [];
  const last = (preset && preset.last) || {{}};
  for (const cls of Object.keys(CLASSES)) {{
    const devs = last[cls] || {{}};
    for (const idx of Object.keys(devs)) {{
      const c = devs[idx].color;
      if (c) out.push('#' + c);
    }}
  }}
  return out.slice(0, 8);
}}
function countPresetDevices(preset) {{
  const last = (preset && preset.last) || {{}};
  let n = 0;
  for (const cls of Object.keys(last)) {{
    n += Object.keys(last[cls] || {{}}).length;
  }}
  return n;
}}

async function applyPreset(name) {{
  toast('→ preset: ' + name, '');
  const r = await fetch('/api/presets/' + encodeURIComponent(name) + '/apply', {{ method: 'POST' }});
  const t = await r.text();
  toast((r.ok ? '✓ ' : '✗ ') + name + (r.ok ? '' : '\\n' + t.slice(0, 200)), r.ok ? 'ok' : 'err');
  await refreshState();
}}

async function deletePreset(name) {{
  if (!confirm('delete preset ' + name + '?')) return;
  const r = await fetch('/api/presets/' + encodeURIComponent(name), {{ method: 'DELETE' }});
  const t = await r.text();
  toast((r.ok ? '✓ ' : '✗ ') + t.slice(0, 200), r.ok ? 'ok' : 'err');
  await refreshState();
}}

async function savePresetWithName(name) {{
  const r = await fetch('/api/presets', {{
    method: 'POST',
    headers: {{ 'content-type': 'application/json' }},
    body: JSON.stringify({{ name }}),
  }});
  const t = await r.text();
  toast((r.ok ? '✓ ' : '✗ ') + t.slice(0, 200), r.ok ? 'ok' : 'err');
  await refreshState();
}}

function openSaveModal() {{
  const m = $('#modal');
  $('#modal-input').value = '';
  m.classList.add('show');
  $('#modal-input').focus();
}}
function closeModal() {{ $('#modal').classList.remove('show'); }}

// ---- takeover ----

function renderTakeover() {{
  const row = $('#takeover'); const btn = $('#override'); const title = $('#takeover-title');
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

// ---- per-class panels ----

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
    panel.appendChild(buildControls(cls, devs, last));
    root.appendChild(panel);
  }}
}}

function buildControls(cls, devs, last) {{
  const wrap = document.createElement('div');
  wrap.className = 'controls';
  const sel = selectedIdx(cls);
  const active = activeDevicesForClass(cls);
  const sample = active[0] || devs[0];
  const lastDev = sel !== 'all' ? (last[String(sel)] || {{}}) : (last[String(sample.index)] || {{}});

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
    toast((r.ok ? '✓ ' : '✗ ') + cls + ' · ' + payload.mode + (r.ok ? '' : '\\n' + t.slice(0, 200)),
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

// ---- header buttons ----

async function panicRestore() {{
  toast('→ restoring keyleds ...', '');
  const r = await fetch('/api/recover', {{ method: 'POST' }});
  const t = await r.text();
  toast((r.ok ? '✓ ' : '✗ ') + 'keyleds restored' + (r.ok ? '' : '\\n' + t.slice(0, 200)), r.ok ? 'ok' : 'err');
  await refreshState();
}}

async function resumeAnimation() {{
  toast('→ resuming animation ...', '');
  const r = await fetch('/api/revert', {{ method: 'POST' }});
  const t = await r.text();
  toast((r.ok ? '✓ ' : '✗ ') + t.slice(0, 200), r.ok ? 'ok' : 'err');
}}

// ---- refresh + boot ----

async function refreshState(opts) {{
  opts = opts || {{}};
  const r = await fetch('/api/state-full');
  if (!r.ok) {{ toast('state fetch failed', 'err'); return; }}
  const j = await r.json();
  state.override = !!j.override;
  state.lastByClass = j.last || {{}};
  state.presets = j.presets || {{}};
  state.history = j.history || [];
  state.historyPtr = (typeof j.history_ptr === 'number') ? j.history_ptr : -1;
  if (!opts.skipDevices) state.devicesByClass = j.devices || {{}};
  renderTakeover(); renderHistory(); renderPresets(); renderClasses();
}}

$('#undo').addEventListener('click', doUndo);
$('#redo').addEventListener('click', doRedo);
$('#panic').addEventListener('click', panicRestore);
$('#resume').addEventListener('click', resumeAnimation);
$('#override').addEventListener('click', toggleOverride);
$('#apply-color-all').addEventListener('click', paintEverything);
$('#save-preset').addEventListener('click', openSaveModal);
$('#modal-cancel').addEventListener('click', closeModal);
$('#modal-ok').addEventListener('click', async () => {{
  const name = $('#modal-input').value.trim();
  if (!name) return;
  closeModal();
  await savePresetWithName(name);
}});
$('#modal-input').addEventListener('keydown', (e) => {{
  if (e.key === 'Enter') $('#modal-ok').click();
  else if (e.key === 'Escape') closeModal();
}});
document.addEventListener('keydown', (e) => {{
  if (e.target && (e.target.tagName === 'INPUT' || e.target.tagName === 'SELECT')) return;
  if ((e.ctrlKey || e.metaKey) && e.key === 'z' && !e.shiftKey) {{ e.preventDefault(); doUndo(); }}
  else if ((e.ctrlKey || e.metaKey) && (e.key === 'y' || (e.key === 'z' && e.shiftKey))) {{ e.preventDefault(); doRedo(); }}
}});

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
    history_summary = [{"ts": h.get("ts"), "label": h.get("label")} for h in state.get("history", [])]
    return web.json_response({
        "override": bool(state.get("override")),
        "last": state.get("last", {}),
        "history": history_summary,
        "history_ptr": state.get("history_ptr", -1),
        "presets": state.get("presets", {}),
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
    cls = payload.get("class") or "?"
    mode = payload.get("mode") or "?"
    color = payload.get("color") or ""
    label = f"{cls} · {mode}" + (f" #{color}" if color else "")
    status, body = await apply_settings(payload, history_label=label)
    return web.Response(text=body, status=status)


async def api_scene(request: web.Request) -> web.Response:
    payload = await request.json()
    scene = (payload.get("scene") or "").strip()
    color = _normalize_color(payload.get("color"))
    if not scene:
        return web.Response(text="missing scene", status=400)
    status, body = await apply_scene(scene, override_color=color)
    return web.Response(text=body, status=status)


async def api_override(request: web.Request) -> web.Response:
    payload = await request.json()
    enabled = bool(payload.get("enabled"))
    msg = await set_override(enabled)
    return web.Response(text=msg)


async def api_recover(_: web.Request) -> web.Response:
    msg = await set_override(False)
    return web.Response(text=msg)


async def api_revert(_: web.Request) -> web.Response:
    msg = await revert_to_animation()
    return web.Response(text=msg)


async def api_undo(_: web.Request) -> web.Response:
    status, body = await history_step(-1)
    return web.Response(text=body, status=status)


async def api_redo(_: web.Request) -> web.Response:
    status, body = await history_step(+1)
    return web.Response(text=body, status=status)


async def api_presets_list(_: web.Request) -> web.Response:
    state = load_state()
    return web.json_response(state.get("presets", {}))


async def api_presets_save(request: web.Request) -> web.Response:
    payload = await request.json()
    name = (payload.get("name") or "").strip()
    status, body = await preset_save(name)
    return web.Response(text=body, status=status)


async def api_presets_delete(request: web.Request) -> web.Response:
    name = request.match_info["name"]
    status, body = await preset_delete(name)
    return web.Response(text=body, status=status)


async def api_presets_apply(request: web.Request) -> web.Response:
    name = request.match_info["name"]
    status, body = await preset_apply(name)
    return web.Response(text=body, status=status)


async def api_healthz(_: web.Request) -> web.Response:
    return web.Response(text="ok")


async def page_index(_: web.Request) -> web.Response:
    return web.Response(text=_index_html(), content_type="text/html")


async def page_device_redirect(_: web.Request) -> web.Response:
    raise web.HTTPFound("/")


def main() -> None:
    migrate_state()
    app = web.Application()
    app.on_startup.append(startup_recovery)
    app.add_routes([
        web.get("/", page_index),
        web.get("/d/{cls}", page_device_redirect),
        web.get("/healthz", api_healthz),
        web.get("/api/state", api_state),
        web.get("/api/state-full", api_state_full),
        web.get("/api/devices/{cls}", api_devices),
        web.post("/api/apply", api_apply),
        web.post("/api/scene", api_scene),
        web.post("/api/override", api_override),
        web.post("/api/recover", api_recover),
        web.post("/api/revert", api_revert),
        web.post("/api/undo", api_undo),
        web.post("/api/redo", api_redo),
        web.get("/api/presets", api_presets_list),
        web.post("/api/presets", api_presets_save),
        web.delete("/api/presets/{name}", api_presets_delete),
        web.post("/api/presets/{name}/apply", api_presets_apply),
    ])
    web.run_app(
        app,
        host=os.environ.get("RGB_HOST", "0.0.0.0"),
        port=int(os.environ.get("RGB_PORT", "6681")),
    )


if __name__ == "__main__":
    main()
