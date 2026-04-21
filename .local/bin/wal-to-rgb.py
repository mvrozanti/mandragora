import json
from pathlib import Path
from openrgb import OpenRGBClient
from openrgb.utils import RGBColor, DeviceType

colors_path = Path.home() / ".cache/wal/colors.json"

if not colors_path.exists():
    raise SystemExit(0)

data = json.loads(colors_path.read_text())
palette = [data["colors"][f"color{i}"].lstrip("#") for i in range(16)]
# palette[0] is the (dark) bg, palette[8] a dim bg — skip those for device accents
slots = [palette[i] for i in (1, 2, 3, 4, 5, 6)]


def from_hex(h):
    return RGBColor(int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def is_owned_elsewhere(device):
    # keyledsd owns the keyboard; hid-wrapper (rivalcfg) owns steelseries mice
    try:
        if device.type == DeviceType.KEYBOARD:
            return True
    except Exception:
        pass
    name = (device.name or "").lower()
    return (
        "keyboard" in name
        or "logitech" in name
        or "g910" in name
        or "steelseries" in name
        or "rival" in name
    )


try:
    client = OpenRGBClient()
except Exception as exc:
    raise SystemExit(f"wal-to-rgb: cannot reach openrgb daemon: {exc}")

for idx, device in enumerate(client.devices):
    if is_owned_elsewhere(device):
        continue
    color = from_hex(slots[idx % len(slots)])
    for mode in ("Direct", "direct"):
        try:
            device.set_mode(mode)
            break
        except Exception:
            continue
    try:
        device.set_color(color)
    except Exception:
        pass
