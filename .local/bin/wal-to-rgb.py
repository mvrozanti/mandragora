import json
import sys
import colorsys
from pathlib import Path
from openrgb import OpenRGBClient
from openrgb.utils import RGBColor

FAN_LEDS = 8
STOPS_PER_FAN = 3
CHAIN_LENGTH = 60
PALETTE_INDICES = [2, 6, 5, 1, 4, 3]
RAM_LEDS_PER_STOP = 2
RAM_STOPS = 4

def from_hex(h):
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    h_val, s_val, v_val = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    s_val = 1.0
    v_val = 1.0
    r, g, b = colorsys.hsv_to_rgb(h_val, s_val, v_val)
    return RGBColor(int(r * 255), int(g * 255), int(b * 255))

colors_path = Path.home() / ".cache/wal/colors.json"
if not colors_path.exists():
    sys.exit(0)

try:
    data = json.loads(colors_path.read_text())
    palette = [data["colors"][f"color{i}"].lstrip("#") for i in range(16)]
    contrast_stops = [from_hex(palette[i]) for i in PALETTE_INDICES]
except Exception:
    sys.exit(1)

try:
    client = OpenRGBClient()
except Exception:
    sys.exit(1)

def fan_chain_colors():
    out = []
    for i in range(CHAIN_LENGTH):
        fan_idx = i // FAN_LEDS
        within_fan = i % FAN_LEDS
        stop_in_fan = (within_fan * STOPS_PER_FAN) // FAN_LEDS
        color_idx = (fan_idx * STOPS_PER_FAN + stop_in_fan) % len(contrast_stops)
        out.append(contrast_stops[color_idx])
    return out

def ram_colors(led_count):
    out = []
    for i in range(led_count):
        color_idx = (i // RAM_LEDS_PER_STOP) % RAM_STOPS
        out.append(contrast_stops[color_idx])
    return out

for device in client.devices:
    name = (device.name or "").lower()
    if any(x in name for x in ["keyboard", "logitech", "mouse", "steelseries", "rival"]):
        continue

    for mode in ("Direct", "direct", "Static", "static"):
        try:
            device.set_mode(mode)
            break
        except Exception:
            continue

    if "aorus" in name or "gigabyte" in name:
        for zone in device.zones:
            if "D_LED" in zone.name:
                zone.resize(CHAIN_LENGTH)
                zone.set_colors(fan_chain_colors())
    elif any(x in name for x in ["dram", "ene", "xpg"]):
        for zone in device.zones:
            zone.set_colors(ram_colors(len(zone.leds)))
    else:
        device.set_color(contrast_stops[0])

    try:
        device.show()
    except Exception:
        pass
