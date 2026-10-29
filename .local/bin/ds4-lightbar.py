import colorsys
import json
import signal
import sys
from pathlib import Path

HOME = Path.home()
THEME_PATH = HOME / ".cache/matugen/hub-theme.json"
PALETTE_PATH = HOME / ".cache/matugen/colors.json"
RGB_STATE_PATH = HOME / ".cache/hid-config/state"
POWER_SUPPLY = Path("/sys/class/power_supply")
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


def rgb_enabled():
    try:
        return RGB_STATE_PATH.read_text().strip() != "False"
    except OSError:
        return True


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


def write_brightness(led, value):
    path = led / "brightness"
    try:
        if path.read_text().strip() == str(value):
            return
        path.write_text(str(value))
    except OSError as e:
        log(f"{path}: {e}")


def apply():
    accent = accent_hex()
    if accent is None:
        return
    rgb = saturated_rgb(accent)
    enabled = rgb_enabled()
    for supply, leds in controllers():
        factor = battery_factor(supply) if enabled else 0.0
        for name, channel in zip(CHANNELS, rgb):
            write_brightness(leds[name], round(channel * 255 * factor))
        write_brightness(leds["global"], 1 if enabled else 0)


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
