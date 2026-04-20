import json
from pathlib import Path
from openrgb import OpenRGBClient
from openrgb.utils import RGBColor

colors_path = Path.home() / ".cache/wal/colors.json"

if not colors_path.exists():
    raise SystemExit(0)

data = json.loads(colors_path.read_text())
palette = [data["colors"][f"color{i}"].lstrip("#") for i in range(16)]


def from_hex(h):
    return RGBColor(int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


client = OpenRGBClient()
color = from_hex(palette[1])
for device in client.devices:
    device.set_color(color)
