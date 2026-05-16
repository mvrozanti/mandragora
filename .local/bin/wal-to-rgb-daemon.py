import colorsys
import json
import time
from pathlib import Path
from openrgb import OpenRGBClient
from openrgb.utils import RGBColor

FPS = 40
STOPS_PER_SECOND = 10.0
COLORS_PATH = Path.home() / ".cache/matugen/colors.json"
RAM_PALETTE_INDICES = [2, 6, 5, 1]
RAM_LEDS_PER_STOP = 2
CONNECT_BACKOFF_SECONDS = 3
ERROR_THRESHOLD = 5

def from_hex(h):
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    h_val, s_val, v_val = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    s_val = 1.0
    v_val = 1.0
    r, g, b = colorsys.hsv_to_rgb(h_val, s_val, v_val)
    return RGBColor(int(r * 255), int(g * 255), int(b * 255))

def load_palette():
    if not COLORS_PATH.exists():
        return None
    try:
        data = json.loads(COLORS_PATH.read_text())
        palette = [data["colors"][f"color{i}"].lstrip("#") for i in range(16)]
        return [from_hex(palette[i]) for i in RAM_PALETTE_INDICES]
    except Exception:
        return None

def lerp_color(a, b, t):
    return RGBColor(
        int(a.red + (b.red - a.red) * t),
        int(a.green + (b.green - a.green) * t),
        int(a.blue + (b.blue - a.blue) * t),
    )

def animated_colors(stops, led_count, phase):
    n = len(stops)
    out = []
    for i in range(led_count):
        pos = (i / RAM_LEDS_PER_STOP + phase) % n
        idx_a = int(pos) % n
        idx_b = (idx_a + 1) % n
        frac = pos - int(pos)
        out.append(lerp_color(stops[idx_a], stops[idx_b], frac))
    return out

def connect():
    while True:
        try:
            return OpenRGBClient()
        except Exception:
            time.sleep(CONNECT_BACKOFF_SECONDS)

def find_ram_devices(client):
    out = []
    for d in client.devices:
        name = (d.name or "").lower()
        if not any(x in name for x in ["dram", "ene", "xpg"]):
            continue
        for mode in ("Direct", "direct"):
            try:
                d.set_mode(mode)
                break
            except Exception:
                continue
        out.append(d)
    return out

def mtime_or_zero():
    try:
        return COLORS_PATH.stat().st_mtime
    except Exception:
        return 0

def main():
    client = connect()
    ram_devices = find_ram_devices(client)
    palette = load_palette()
    last_mtime = mtime_or_zero()
    phase = 0.0
    frame_dt = 1.0 / FPS
    phase_step = STOPS_PER_SECOND / FPS
    consecutive_errors = 0

    while True:
        frame_start = time.monotonic()

        new_mtime = mtime_or_zero()
        if new_mtime != last_mtime:
            new_palette = load_palette()
            if new_palette:
                palette = new_palette
                last_mtime = new_mtime

        if palette and ram_devices:
            try:
                for d in ram_devices:
                    for zone in d.zones:
                        zone.set_colors(animated_colors(palette, len(zone.leds), phase))
                    d.show()
                consecutive_errors = 0
            except Exception:
                consecutive_errors += 1
                if consecutive_errors >= ERROR_THRESHOLD:
                    try:
                        client.disconnect()
                    except Exception:
                        pass
                    client = connect()
                    ram_devices = find_ram_devices(client)
                    consecutive_errors = 0

        phase = (phase + phase_step) % len(palette) if palette else 0.0

        elapsed = time.monotonic() - frame_start
        sleep_for = frame_dt - elapsed
        if sleep_for > 0:
            time.sleep(sleep_for)

main()
