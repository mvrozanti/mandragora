import json
import sys
import colorsys
from pathlib import Path
from openrgb import OpenRGBClient
from openrgb.utils import RGBColor

STOPS_PER_FAN = 4
RAM_LEDS_PER_STOP = 2
RAM_PALETTE_INDICES = [2, 6, 5, 1]
STATE_PATH = Path.home() / ".cache/hid-config/state"

def is_rgb_on():
    try:
        if STATE_PATH.exists():
            return STATE_PATH.read_text().strip() == "True"
    except Exception:
        pass
    return True

RGB_ON = is_rgb_on()
BLACK = RGBColor(0, 0, 0)

def from_hex(h):
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    h_val, s_val, v_val = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    s_val = 1.0
    v_val = 1.0
    r, g, b = colorsys.hsv_to_rgb(h_val, s_val, v_val)
    return RGBColor(int(r * 255), int(g * 255), int(b * 255))

def hue_of(h):
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    return colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)[0]

def pick_distinct_stops(palette_hex, n):
    candidates = sorted(
        [(hue_of(palette_hex[i]), i) for i in range(1, 9)]
    )
    step = len(candidates) / n
    chosen = [candidates[int(k * step)][1] for k in range(n)]
    return [from_hex(palette_hex[i]) for i in chosen]


fan_stops = []
ram_stops = []
if RGB_ON:
    colors_path = Path.home() / ".cache/matugen/colors.json"
    if not colors_path.exists():
        sys.exit(0)

    try:
        data = json.loads(colors_path.read_text())
        palette = [data["colors"][f"color{i}"].lstrip("#") for i in range(16)]
        fan_stops = pick_distinct_stops(palette, STOPS_PER_FAN)
        ram_stops = [from_hex(palette[i]) for i in RAM_PALETTE_INDICES]
    except Exception:
        sys.exit(1)

try:
    client = OpenRGBClient(protocol_version=3)
except Exception:
    sys.exit(1)


def ram_colors(led_count):
    out = []
    for i in range(led_count):
        out.append(ram_stops[(i // RAM_LEDS_PER_STOP) % len(ram_stops)])
    return out

def ensure_direct(device):
    if device.modes[device.active_mode].name.lower() == "direct":
        return
    for mode in ("Direct", "direct", "Static", "static"):
        try:
            device.set_mode(mode)
            return
        except Exception:
            continue

def set_static(device, color):
    static = next(m for m in device.modes if m.name.lower() == "static")
    static.colors = [color]
    device.set_mode(static)

for device in client.devices:
    name = (device.name or "").lower()
    if any(x in name for x in ["keyboard", "logitech", "mouse", "steelseries", "rival"]):
        continue

    if "aorus" in name or "gigabyte" in name:
        set_static(device, fan_stops[0] if RGB_ON else BLACK)
        continue

    ensure_direct(device)

    if any(x in name for x in ["dram", "ene", "xpg"]):
        count = len(device.leds)
        device.set_colors(ram_colors(count) if RGB_ON else [BLACK] * count, fast=True)
    else:
        device.set_color(fan_stops[0] if RGB_ON else BLACK)
