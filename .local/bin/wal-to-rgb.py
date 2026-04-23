import json
import sys
import colorsys
from pathlib import Path
from openrgb import OpenRGBClient
from openrgb.utils import RGBColor

FAN_LEDS = 8
STOPS_PER_FAN = 4
CHAIN_LENGTH = 60
RAM_LEDS_PER_STOP = 2
RAM_PALETTE_INDICES = [2, 6, 5, 1]

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

def fan_band_indices():
    base = FAN_LEDS // STOPS_PER_FAN
    sizes = [base] * STOPS_PER_FAN
    remainder = FAN_LEDS - base * STOPS_PER_FAN
    left, right = 0, STOPS_PER_FAN - 1
    while remainder > 0:
        sizes[left] += 1
        remainder -= 1
        left += 1
        if remainder > 0:
            sizes[right] += 1
            remainder -= 1
            right -= 1
    indices = []
    for stop_idx, size in enumerate(sizes):
        indices.extend([stop_idx] * size)
    return indices

colors_path = Path.home() / ".cache/wal/colors.json"
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
    client = OpenRGBClient()
except Exception:
    sys.exit(1)

def fan_chain_colors():
    band = fan_band_indices()
    out = []
    for i in range(CHAIN_LENGTH):
        out.append(fan_stops[band[i % FAN_LEDS]])
    return out

def ram_colors(led_count):
    out = []
    for i in range(led_count):
        out.append(ram_stops[(i // RAM_LEDS_PER_STOP) % len(ram_stops)])
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
        device.set_color(fan_stops[0])

    try:
        device.show()
    except Exception:
        pass
