#!/usr/bin/env python3
import colorsys
import json
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
RES = HERE.parent / "app/src/main/res"
BUCKETS = 12
HOME_BUCKET = 8
DEFAULT = "gray"
glyph = json.loads((HERE / "glyph.json").read_text())


def rotate(color: str, degrees: float) -> str:
    r, g, b = (int(color[i:i + 2], 16) / 255 for i in (1, 3, 5))
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    r, g, b = colorsys.hsv_to_rgb((h + degrees / 360) % 1, s, v)
    return "#%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255))


def gray(color: str) -> str:
    channels = [int(color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    linear = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in channels]
    luminance = 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    level = 12.92 * luminance if luminance <= 0.0031308 else 1.055 * luminance ** (1 / 2.4) - 0.055
    return "#%02x%02x%02x" % ((round(level * 255),) * 3)


def span(path: str) -> tuple[float, float, float]:
    numbers = [float(n) for n in re.findall(r"-?\d+\.?\d*", path)]
    xs, ys = numbers[0::2], numbers[1::2]
    return (min(xs) + max(xs)) / 2, min(ys), max(ys)


def gradient_path(path: str, start: str, end: str) -> str:
    x, top, bottom = span(path)
    return f'''    <path android:pathData="{path}">
        <aapt:attr name="android:fillColor">
            <gradient
                android:type="linear"
                android:startX="{x:.1f}"
                android:startY="{top:.1f}"
                android:endX="{x:.1f}"
                android:endY="{bottom:.1f}"
                android:startColor="{start}"
                android:endColor="{end}" />
        </aapt:attr>
    </path>
'''


VECTOR = '''<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:aapt="http://schemas.android.com/aapt"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
'''

colors = glyph["colors"]
(RES / "drawable").mkdir(parents=True, exist_ok=True)
(RES / "mipmap-anydpi-v26").mkdir(parents=True, exist_ok=True)
(RES / "values").mkdir(parents=True, exist_ok=True)


def write_variant(name: str, paint) -> str:
    fg = VECTOR
    fg += gradient_path(glyph["body"], paint(colors["body_top"]), paint(colors["body_bottom"]))
    fg += gradient_path(glyph["leaf"], paint(colors["leaf_top"]), paint(colors["leaf_bottom"]))
    fg += "</vector>\n"
    (RES / "drawable" / f"ic_launcher_fg_{name}.xml").write_text(fg)
    (RES / "mipmap-anydpi-v26" / f"ic_launcher_{name}.xml").write_text(f'''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_plate_{name}" />
    <foreground android:drawable="@drawable/ic_launcher_fg_{name}" />
    <monochrome android:drawable="@drawable/ic_launcher_mono" />
</adaptive-icon>
''')
    return paint(colors["plate"])


plates = {}
for k in range(BUCKETS):
    shift = (k - HOME_BUCKET) * (360 / BUCKETS)
    plates[str(k)] = write_variant(str(k), lambda color: rotate(color, shift))
plates[DEFAULT] = write_variant(DEFAULT, gray)

mono = VECTOR.replace('    xmlns:aapt="http://schemas.android.com/aapt"\n', "")
for key in ("body", "leaf"):
    mono += f'    <path\n        android:fillColor="#000000"\n        android:pathData="{glyph[key]}" />\n'
mono += "</vector>\n"
(RES / "drawable" / "ic_launcher_mono.xml").write_text(mono)

values = '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
for name, plate in plates.items():
    values += f'    <color name="ic_plate_{name}">{plate}</color>\n'
values += "</resources>\n"
(RES / "values" / "ic_launcher_colors.xml").write_text(values)

if "--aliases" in sys.argv:
    for k in range(BUCKETS):
        enabled = "true" if k == HOME_BUCKET else "false"
        print(f'''        <activity-alias
            android:name=".Icon{k}"
            android:enabled="{enabled}"
            android:exported="true"
            android:icon="@mipmap/ic_launcher_{k}"
            android:roundIcon="@mipmap/ic_launcher_{k}"
            android:targetActivity=".MainActivity">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity-alias>
''')
print(f"wrote {BUCKETS} hue variants, the {DEFAULT} default and the monochrome layer under {RES}")
