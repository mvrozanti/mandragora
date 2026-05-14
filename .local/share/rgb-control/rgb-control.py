#!/usr/bin/env python3
"""rgb-control — per-device RGB web UI for Mandragora.

Drives openrgb directly via short-lived CLI invocations. RAM + motherboard
use the standard "safe" openrgb config. Mouse + keyboard require enabling
HID detectors that conflict with keyledsd, so they are gated behind an
"override keyleds" toggle. Recovery is layered:

  - every page renders a "restore keyleds" panic button,
  - turning the override off is idempotent and always restarts keyledsd,
  - the systemd unit's ExecStopPost restarts keyledsd if the service dies,
  - on startup the service forces override=false and ensures keyledsd is up.
"""
from __future__ import annotations

import asyncio
import json
import logging
import os
import re
import shutil
import time
from pathlib import Path
from typing import Any

from aiohttp import web

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

ENUM_TTL_S = 8.0


def load_state() -> dict[str, Any]:
    try:
        return json.loads(STATE_FILE.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return {"override": False}


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


def config_dir_for_class(cls: str) -> Path:
    return HID_CONFIG if DEVICE_CLASSES[cls]["hid"] else SAFE_CONFIG


_enum_cache: dict[str, tuple[float, list[dict[str, Any]]]] = {}


async def list_devices(config_dir: Path) -> list[dict[str, Any]]:
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
    if info["hid"] and not load_state().get("override"):
        return []
    all_devs = await list_devices(config_dir_for_class(cls))
    return [d for d in all_devs if (d.get("type") or "").lower() == info["type"].lower()]


_HEX_COLOR = re.compile(r"^[0-9A-Fa-f]{6}$")


def _normalize_color(c: str | None) -> str | None:
    if c is None:
        return None
    c = c.strip().lstrip("#")
    if not _HEX_COLOR.match(c):
        return None
    return c.upper()


async def apply_settings(payload: dict[str, Any]) -> tuple[int, str]:
    cls = payload.get("class")
    if cls not in DEVICE_CLASSES:
        return 400, f"unknown class: {cls}"
    info = DEVICE_CLASSES[cls]
    if info["hid"] and not load_state().get("override"):
        return 409, "override keyleds is off — enable it to control mouse/keyboard"
    device = (payload.get("device") or "").strip()
    if not device:
        return 400, "missing device name"
    mode = (payload.get("mode") or "").strip()
    if not mode:
        return 400, "missing mode"
    color = _normalize_color(payload.get("color"))
    zone = payload.get("zone")
    speed = payload.get("speed")
    brightness = payload.get("brightness")

    args = [OPENRGB, "--config", str(config_dir_for_class(cls)), "--noautoconnect",
            "--device", device]
    if zone is not None and zone != "":
        args += ["--zone", str(int(zone))]
    args += ["--mode", mode]
    if color is not None:
        args += ["--color", color]
    if speed is not None and speed != "":
        args += ["--speed", str(int(speed))]
    if brightness is not None and brightness != "":
        args += ["--brightness", str(int(brightness))]

    log.info("apply: %s", " ".join(args[1:]))
    proc = await asyncio.create_subprocess_exec(
        *args, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT,
    )
    out, _ = await proc.communicate()
    text = out.decode(errors="replace")[-600:]
    _enum_cache.clear()
    return (200 if proc.returncode == 0 else 500), text


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
        log.warning("override left enabled across restart — forcing off")
        await restart_keyleds()
        save_state({"override": False})


# ---------------------------------------------------------------- frontend

STYLE = """
:root {
  --bg: #050805; --panel: #0a0e0a; --fg: #b8ffc4; --accent: #00ff66;
  --dim: #4a6a4e; --line: #1a2418; --hover: #0f1810; --warn: #ff6b6b;
  --warn-bg: #1a0808;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body { background: var(--bg); color: var(--fg);
       font-family: ui-monospace, "Iosevka", monospace;
       min-height: 100vh; padding: 1.5rem 1.25rem; }
.wrap { max-width: 900px; margin: 0 auto; }
header { display: flex; justify-content: space-between; align-items: center;
         border-bottom: 1px solid var(--line); padding-bottom: 1rem;
         margin-bottom: 1.5rem; gap: 1rem; flex-wrap: wrap; }
h1 { font-size: 1rem; font-weight: normal; }
h1::before { content: "$ "; color: var(--accent); }
.crumbs a { color: var(--accent); text-decoration: none; }
.crumbs a:hover { text-decoration: underline; }
.panic { background: var(--warn-bg); color: var(--warn); border: 1px solid var(--warn);
         padding: 0.5rem 0.9rem; font: inherit; cursor: pointer; }
.panic:hover { background: var(--warn); color: var(--bg); }
.grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
        gap: 0.8rem; margin-bottom: 1.5rem; }
.card { background: var(--panel); border: 1px solid var(--line); padding: 1rem;
        text-decoration: none; color: var(--fg); display: block; transition: all 0.12s; }
.card:hover { border-color: var(--accent); background: var(--hover); }
.card .name { color: var(--accent); font-size: 1.05rem; }
.card .sub { color: var(--dim); font-size: 0.8rem; margin-top: 0.4rem; }
.card.disabled { opacity: 0.4; pointer-events: none; }
.toggle-row { display: flex; align-items: center; gap: 0.8rem;
              padding: 0.8rem; border: 1px solid var(--line); background: var(--panel);
              margin-bottom: 1.5rem; flex-wrap: wrap; }
.toggle-row .desc { color: var(--dim); font-size: 0.8rem; flex: 1; min-width: 200px; }
.toggle-row.on { border-color: var(--warn); }
.toggle-row .label { color: var(--fg); }
.toggle-row.on .label { color: var(--warn); }
.switch { background: var(--bg); border: 1px solid var(--line); color: var(--fg);
          padding: 0.5rem 0.9rem; font: inherit; cursor: pointer; }
.switch.on { background: var(--warn); color: var(--bg); border-color: var(--warn); }
.row { display: flex; gap: 0.6rem; align-items: center; margin: 0.6rem 0; flex-wrap: wrap; }
.row label { color: var(--dim); min-width: 90px; font-size: 0.85rem; }
select, input[type=color], input[type=range], button.apply {
  background: var(--panel); border: 1px solid var(--line); color: var(--fg);
  padding: 0.4rem 0.6rem; font: inherit;
}
input[type=color] { padding: 0; width: 64px; height: 32px; }
input[type=range] { padding: 0; }
button.apply { cursor: pointer; padding: 0.6rem 1.2rem; }
button.apply:hover { border-color: var(--accent); background: var(--hover); }
button.apply:disabled { opacity: 0.4; cursor: not-allowed; }
.panel { background: var(--panel); border: 1px solid var(--line); padding: 1rem;
         margin-bottom: 1rem; }
.warn { border-color: var(--warn); background: var(--warn-bg); color: var(--warn); }
#status { padding: 0.75rem; border: 1px solid var(--line); background: var(--panel);
          font-size: 0.8rem; color: var(--dim); min-height: 2.5rem;
          white-space: pre-wrap; margin-top: 1rem; }
#status.ok { color: var(--accent); }
#status.err { color: var(--warn); border-color: var(--warn); }
"""


def _page(body: str, *, title: str = "rgb", crumb: str | None = None) -> str:
    crumb_html = '<a href="/">rgb</a>' if crumb else '<span>rgb</span>'
    if crumb:
        crumb_html += f' / <span>{crumb}</span>'
    return f"""<!DOCTYPE html>
<html lang="en"><head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title} · mvr.ac</title><style>{STYLE}</style>
</head><body><div class="wrap">
<header>
  <div>
    <h1>{title}</h1>
    <div class="crumbs">{crumb_html}</div>
  </div>
  <button class="panic" id="panic">restore keyleds</button>
</header>
{body}
<div id="status">ready</div>
</div>
<script>
async function panicRestore() {{
  const s = document.getElementById('status');
  s.className = ''; s.textContent = '→ restoring keyleds ...';
  try {{
    const r = await fetch('/api/recover', {{ method: 'POST' }});
    const t = await r.text();
    s.className = r.ok ? 'ok' : 'err';
    s.textContent = (r.ok ? '✓ ' : '✗ ') + 'keyleds restored\\n' + t.slice(0, 400);
    if (r.ok) setTimeout(() => location.reload(), 600);
  }} catch (e) {{
    s.className = 'err';
    s.textContent = '✗ ' + e.message;
  }}
}}
document.getElementById('panic').addEventListener('click', panicRestore);
</script>
</body></html>"""


def _landing_body(state: dict[str, Any]) -> str:
    override = bool(state.get("override"))
    toggle_class = "toggle-row on" if override else "toggle-row"
    btn_class = "switch on" if override else "switch"
    btn_label = "ON — keyleds stopped" if override else "OFF — keyleds active"
    cards = []
    for key, info in DEVICE_CLASSES.items():
        cls = "card disabled" if (info["hid"] and not override) else "card"
        sub = "requires override" if (info["hid"] and not override) else info["type"]
        cards.append(
            f'<a class="{cls}" href="/d/{key}"><div class="name">{info["label"]}</div>'
            f'<div class="sub">{sub}</div></a>'
        )
    cur_js = "true" if override else "false"
    return f"""
<div class="{toggle_class}">
  <span class="label">override keyleds</span>
  <span class="desc">When ON, keyledsd is stopped so OpenRGB can drive the keyboard
    + mouse via HID. The keyboard loses its per-key effects until you toggle OFF
    (or hit "restore keyleds" — always available, top right).</span>
  <button class="{btn_class}" id="override">{btn_label}</button>
</div>
<div class="grid">
{''.join(cards)}
</div>
<script>
document.getElementById('override').addEventListener('click', async () => {{
  const cur = {cur_js};
  const s = document.getElementById('status');
  s.className = ''; s.textContent = '→ ' + (cur ? 'releasing keyboard ...' : 'taking keyboard ...');
  try {{
    const r = await fetch('/api/override', {{
      method: 'POST',
      headers: {{ 'content-type': 'application/json' }},
      body: JSON.stringify({{ enabled: !cur }}),
    }});
    const t = await r.text();
    s.className = r.ok ? 'ok' : 'err';
    s.textContent = (r.ok ? '✓ ' : '✗ ') + t.slice(0, 400);
    if (r.ok) setTimeout(() => location.reload(), 600);
  }} catch (e) {{ s.className = 'err'; s.textContent = '✗ ' + e.message; }}
}});
</script>
"""


async def page_index(_: web.Request) -> web.Response:
    return web.Response(text=_page(_landing_body(load_state()), title="rgb"),
                        content_type="text/html")


def _device_body(cls: str) -> str:
    info = DEVICE_CLASSES[cls]
    needs_override = info["hid"]
    warn_block = ""
    if needs_override:
        warn_block = """
<div class="panel warn" id="override-warn" hidden>
  Override is OFF — enable it on the landing page to control this device.
</div>
"""
    needs_js = "true" if needs_override else "false"
    return f"""
{warn_block}
<div class="panel">
  <div class="row">
    <label for="device">device</label>
    <select id="device"></select>
  </div>
  <div class="row">
    <label for="zone">zone</label>
    <select id="zone"></select>
  </div>
  <div class="row">
    <label for="mode">mode</label>
    <select id="mode"></select>
  </div>
  <div class="row">
    <label for="color">color</label>
    <input type="color" id="color" value="#00ff66">
  </div>
  <div class="row">
    <label for="speed">speed</label>
    <input type="range" id="speed" min="0" max="100" value="50">
    <span id="speed-val" class="desc">50</span>
  </div>
  <div class="row">
    <label for="brightness">brightness</label>
    <input type="range" id="brightness" min="0" max="100" value="100">
    <span id="brightness-val" class="desc">100</span>
  </div>
  <div class="row">
    <button class="apply" id="apply">apply</button>
  </div>
</div>
<script>
const CLS = {json.dumps(cls)};
const NEEDS_OVERRIDE = {needs_js};
const els = {{
  device: document.getElementById('device'),
  zone: document.getElementById('zone'),
  mode: document.getElementById('mode'),
  color: document.getElementById('color'),
  speed: document.getElementById('speed'),
  speedVal: document.getElementById('speed-val'),
  brightness: document.getElementById('brightness'),
  brightnessVal: document.getElementById('brightness-val'),
  apply: document.getElementById('apply'),
  warn: document.getElementById('override-warn'),
  status: document.getElementById('status'),
}};
els.speed.addEventListener('input', () => els.speedVal.textContent = els.speed.value);
els.brightness.addEventListener('input', () => els.brightnessVal.textContent = els.brightness.value);

let devices = [];
function fillDevices(list) {{
  els.device.innerHTML = '';
  for (const d of list) {{
    const opt = document.createElement('option');
    opt.value = d.name;
    opt.dataset.idx = d.index;
    opt.textContent = d.name;
    els.device.appendChild(opt);
  }}
  if (list.length) syncFromDevice();
}}
function currentDevice() {{
  return devices.find(d => d.name === els.device.value);
}}
function syncFromDevice() {{
  const d = currentDevice();
  if (!d) return;
  els.zone.innerHTML = '';
  const allOpt = document.createElement('option');
  allOpt.value = ''; allOpt.textContent = '(all)';
  els.zone.appendChild(allOpt);
  (d.zones || []).forEach((z, i) => {{
    const opt = document.createElement('option');
    opt.value = String(i); opt.textContent = i + ': ' + z;
    els.zone.appendChild(opt);
  }});
  els.mode.innerHTML = '';
  for (const m of (d.modes || [])) {{
    const opt = document.createElement('option');
    opt.value = m; opt.textContent = m;
    els.mode.appendChild(opt);
  }}
}}
els.device.addEventListener('change', syncFromDevice);

async function load() {{
  const r = await fetch('/api/devices/' + CLS);
  const j = await r.json();
  devices = j.devices || [];
  if (NEEDS_OVERRIDE && !j.override) {{
    if (els.warn) els.warn.hidden = false;
    els.apply.disabled = true;
  }}
  fillDevices(devices);
  if (!devices.length) {{
    els.status.textContent = NEEDS_OVERRIDE && !j.override
      ? 'enable override on the landing page first'
      : 'no devices in this class';
  }}
}}

els.apply.addEventListener('click', async () => {{
  const payload = {{
    class: CLS,
    device: els.device.value,
    mode: els.mode.value,
    color: els.color.value.replace('#', ''),
    zone: els.zone.value,
    speed: els.speed.value,
    brightness: els.brightness.value,
  }};
  els.status.className = '';
  els.status.textContent = '→ ' + payload.mode + ' ' + payload.device + ' ...';
  try {{
    const r = await fetch('/api/apply', {{
      method: 'POST',
      headers: {{ 'content-type': 'application/json' }},
      body: JSON.stringify(payload),
    }});
    const t = await r.text();
    els.status.className = r.ok ? 'ok' : 'err';
    els.status.textContent = (r.ok ? '✓ ' : '✗ ') + payload.mode + '\\n' + t.slice(0, 400);
  }} catch (e) {{ els.status.className = 'err'; els.status.textContent = '✗ ' + e.message; }}
}});

load();
</script>
"""


async def page_device(request: web.Request) -> web.Response:
    cls = request.match_info["cls"]
    if cls not in DEVICE_CLASSES:
        return web.Response(status=404, text=f"unknown device class: {cls}")
    info = DEVICE_CLASSES[cls]
    return web.Response(
        text=_page(_device_body(cls), title=f"rgb · {info['label'].lower()}", crumb=info["label"]),
        content_type="text/html",
    )


# ------------------------------------------------------------------- api

async def api_state(_: web.Request) -> web.Response:
    return web.json_response(load_state())


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


async def api_override(request: web.Request) -> web.Response:
    payload = await request.json()
    enabled = bool(payload.get("enabled"))
    msg = await set_override(enabled)
    return web.Response(text=msg)


async def api_recover(_: web.Request) -> web.Response:
    msg = await set_override(False)
    return web.Response(text=msg)


def main() -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    app = web.Application()
    app.on_startup.append(startup_recovery)
    app.add_routes([
        web.get("/", page_index),
        web.get("/d/{cls}", page_device),
        web.get("/api/state", api_state),
        web.get("/api/devices/{cls}", api_devices),
        web.post("/api/apply", api_apply),
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
