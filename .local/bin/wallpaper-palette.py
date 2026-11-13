import json
import math
import os
import re
import subprocess
import sys

CANDIDATES = 4
SAMPLE = "48x48!"
MIN_CHROMA = 12
HUE_WINDOW = 30
RESEED_RATIO = 1.15
RESEED_MARGIN = 0.02
SECOND_MIN_SEPARATION = 45
SECOND_MIN_GAIN = 0.15
PALETTE = os.path.expanduser("~/.cache/matugen/palette.json")


def linear(channel):
    c = channel / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def lab_axis(value):
    return value ** (1 / 3) if value > 0.008856 else 7.787 * value + 16 / 116


def chroma_hue(r, g, b):
    r, g, b = linear(r), linear(g), linear(b)
    x = lab_axis((0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047)
    y = lab_axis(0.2126 * r + 0.7152 * g + 0.0722 * b)
    z = lab_axis((0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883)
    a, bb = 500 * (x - y), 200 * (y - z)
    return math.hypot(a, bb), math.degrees(math.atan2(bb, a)) % 360


def hex_hue(color):
    return chroma_hue(*(int(color[i:i + 2], 16) for i in (1, 3, 5)))[1]


def hue_distance(a, b):
    d = abs(a - b) % 360
    return min(d, 360 - d)


def colourful_pixels(path):
    dump = subprocess.run(
        ["magick", path + "[0]", "-resize", SAMPLE, "-alpha", "off", "-depth", "8", "txt:-"],
        capture_output=True, text=True, check=True,
    ).stdout
    pixels = (chroma_hue(*map(int, rgb)) for rgb in re.findall(r"\((\d+),(\d+),(\d+)", dump))
    return [(c, h) for c, h in pixels if c >= MIN_CHROMA]


def scheme(path, index):
    out = subprocess.run(
        ["matugen", "image", path, "--source-color-index", str(index),
         "--dry-run", "--json", "hex", "--include-image-in-json", "true"],
        capture_output=True, text=True,
    ).stdout
    return json.loads(out[out.index("{"):]) if "{" in out else None


def candidates(path):
    found = []
    for index in range(CANDIDATES):
        one = scheme(path, index)
        if one is None:
            break
        found.append(one)
    return found


def choose(pixels, hues):
    total = sum(c for c, _ in pixels)

    def share(accents):
        return sum(c for c, h in pixels if min(hue_distance(h, a) for a in accents) <= HUE_WINDOW) / total

    alone = [share([h]) for h in hues]
    seed = max(range(len(hues)), key=alone.__getitem__)
    if alone[seed] < alone[0] * RESEED_RATIO + RESEED_MARGIN:
        seed = 0
    second, best = None, SECOND_MIN_GAIN
    for k, h in enumerate(hues):
        if k == seed or hue_distance(h, hues[seed]) < SECOND_MIN_SEPARATION:
            continue
        gain = share([hues[seed], h]) - alone[seed]
        if gain > best:
            second, best = k, gain
    return seed, second


def graft_second_accent(base, donor):
    for group in ("colors", "palettes"):
        for role in base.get(group, {}):
            source = role.replace("tertiary", "primary")
            if "tertiary" in role and source in donor.get(group, {}):
                base[group][role] = donor[group][source]
    return base


def build(path):
    pixels = colourful_pixels(path)
    found = candidates(path)
    if not found:
        raise RuntimeError("matugen offered no source colour")
    if not pixels:
        return found[0]
    hues = [hex_hue(c["colors"]["source_color"]["default"]["color"]) for c in found]
    seed, second = choose(pixels, hues)
    if second is None:
        return found[seed]
    return graft_second_accent(found[seed], found[second])


def main():
    args = [a for a in sys.argv[1:] if a != "--json"]
    if len(args) != 1:
        sys.exit("usage: wallpaper-palette [--json] <image>")
    path = args[0]
    try:
        palette = build(path)
    except Exception as error:
        print(f"wallpaper-palette: {error}; using matugen's first colour", file=sys.stderr)
        sys.exit(subprocess.run(
            ["matugen", "image", path, "--source-color-index", "0", "--quiet"]).returncode)
    if "--json" in sys.argv[1:]:
        json.dump(palette, sys.stdout)
        return
    os.makedirs(os.path.dirname(PALETTE), exist_ok=True)
    with open(PALETTE, "w") as handle:
        json.dump(palette, handle)
    sys.exit(subprocess.run(["matugen", "json", PALETTE, "--quiet"]).returncode)


if __name__ == "__main__":
    main()
