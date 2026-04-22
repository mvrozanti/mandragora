import json
import sys
import colorsys
from pathlib import Path
from openrgb import OpenRGBClient
from openrgb.utils import RGBColor

def from_hex(h):
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    h_val, s_val, v_val = colorsys.rgb_to_hsv(r/255, g/255, b/255)
    # Aggressive saturation/value for hardware pop
    s_val = 1.0
    v_val = 1.0
    r, g, b = colorsys.hsv_to_rgb(h_val, s_val, v_val)
    return RGBColor(int(r*255), int(g*255), int(b*255))

colors_path = Path.home() / ".cache/wal/colors.json"
if not colors_path.exists(): sys.exit(0)

try:
    data = json.loads(colors_path.read_text())
    # Selected indices for high contrast (Warm, Warm, Cool, Light, Bold, Base)
    # Using 2 (Rust), 5 (Orange), 6 (Steel Blue) for the primary 3 colors per device
    p = [data["colors"][f"color{i}"].lstrip("#") for i in range(16)]
    # We want a high-contrast cycle
    contrast_stops = [from_hex(p[i]) for i in [2, 6, 5, 1, 4, 3]]
except Exception: sys.exit(1)

try:
    client = OpenRGBClient()
except Exception: sys.exit(1)

for device in client.devices:
    name = (device.name or "").lower()
    if any(x in name for x in ["keyboard", "logitech", "mouse", "steelseries", "rival"]): continue
    
    for mode in ("Direct", "direct", "Static", "static"):
        try:
            device.set_mode(mode)
            break
        except Exception: continue
    
    if "aorus" in name or "gigabyte" in name:
        for zone in device.zones:
            if "D_LED" in zone.name:
                zone.resize(60)
                # 3 colors per fan/device (assuming 15 LEDs per device in the 60-chain)
                # To get 3 colors per fan, we use blocks of 5 LEDs
                colors = []
                for i in range(60):
                    # Each 15-LED segment gets stops 0, 1, 2
                    # The next 15-LED segment gets stops 3, 4, 5
                    # This ensures variety across the whole cooler
                    segment = (i // 15) % 2 # 0 or 1
                    sub_idx = (i // 5) % 3  # 0, 1, or 2
                    color_idx = (segment * 3) + sub_idx
                    colors.append(contrast_stops[color_idx])
                zone.set_colors(colors)
    
    elif any(x in name for x in ["dram", "ene", "xpg"]):
        for zone in device.zones:
            # 8 LEDs on RAM. 4 spots of 2 LEDs each.
            # Using the first 4 contrast stops for distinct colors.
            colors = []
            for i in range(len(zone.leds)):
                color_idx = (i // 2) % 4
                colors.append(contrast_stops[color_idx])
            zone.set_colors(colors)
    else:
        device.set_color(contrast_stops[0])

    try: device.show()
    except Exception: pass
