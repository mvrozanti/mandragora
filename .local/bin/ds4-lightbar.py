import colorsys
import json
import signal
import sys
from pathlib import Path

HOME = Path.home()
THEME_PATH = HOME / ".cache/matugen/hub-theme.json"
PALETTE_PATH = HOME / ".cache/matugen/colors.json"
POWER_SUPPLY = Path("/sys/class/power_supply")
PROC = Path("/proc")
DARK_WHILE_RUNNING = ("steam",)
CHANNELS = ("red", "green", "blue")
TICK_SECONDS = 5
MIN_BRIGHTNESS_FACTOR = 0.04


def log(msg):
    sys.stderr.write(f"ds4-lightbar: {msg}\n")
    sys.stderr.flush()


def accent_hex():
    try:
        return json.loads(THEME_PATH.read_text())["primary"].lstrip("#")
    except (OSError, ValueError, KeyError):
        pass
    try:
        return json.loads(PALETTE_PATH.read_text())["colors"]["color1"].lstrip("#")
    except (OSError, ValueError, KeyError):
        return None


def saturated_rgb(hex_color):
    r, g, b = (int(hex_color[i:i + 2], 16) / 255 for i in (0, 2, 4))
    hue = colorsys.rgb_to_hsv(r, g, b)[0]
    return colorsys.hsv_to_rgb(hue, 1.0, 1.0)


def dark_process_running():
    for entry in PROC.iterdir():
        if not entry.name.isdigit():
            continue
        try:
            if (entry / "comm").read_text().strip() in DARK_WHILE_RUNNING:
                return True
        except OSError:
            continue
    return False


def controllers():
    for supply in sorted(POWER_SUPPLY.glob("ps-controller-battery-*")):
        leds = supply / "device/leds"
        found = {name: next(leds.glob(f"*:{name}"), None) for name in CHANNELS + ("global",)}
        if all(found.values()):
            yield supply, found


def battery_factor(supply):
    try:
        capacity = int((supply / "capacity").read_text())
        status = (supply / "status").read_text().strip()
    except (OSError, ValueError):
        return 1.0
    if status == "Full":
        capacity = 100
    return max(MIN_BRIGHTNESS_FACTOR, min(capacity, 100) / 100)


def write_brightness(led, value, force=False):
    path = led / "brightness"
    try:
        if not force and path.read_text().strip() == str(value):
            return
        path.write_text(str(value))
    except OSError as e:
        log(f"{path}: {e}")


def apply():
    accent = accent_hex()
    if accent is None:
        return
    rgb = saturated_rgb(accent)
    dark = dark_process_running()
    for supply, leds in controllers():
        if dark:
            for name in CHANNELS:
                write_brightness(leds[name], 0, force=True)
            write_brightness(leds["global"], 0, force=True)
            continue
        factor = battery_factor(supply)
        for name, channel in zip(CHANNELS, rgb):
            write_brightness(leds[name], round(channel * 255 * factor))
        write_brightness(leds["global"], 1)


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--once":
        apply()
        return
    signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGUSR1})
    while True:
        apply()
        signal.sigtimedwait({signal.SIGUSR1}, TICK_SECONDS)


if __name__ == "__main__":
    main()
