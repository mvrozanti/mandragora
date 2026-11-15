import colorsys
import json
import pathlib
import re
import subprocess
import sys

from PIL import Image

src = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)
im = Image.open(src).convert("RGB")
W, H = im.size
px = im.load()
plate = px[8, H // 2]


def hsv(c):
    return colorsys.rgb_to_hsv(c[0] / 255, c[1] / 255, c[2] / 255)


ph, ps, pv = hsv(plate)
corner = px[3, 3]
leaf = Image.new("1", im.size, 0)
body = Image.new("1", im.size, 0)
lp, bp = leaf.load(), body.load()


def near(c, ref, tol=28):
    return all(abs(c[i] - ref[i]) <= tol for i in range(3))


plate_mask = Image.new("1", im.size, 0)
pm = plate_mask.load()
for y in range(H):
    for x in range(W):
        if near(px[x, y], plate, 34):
            pm[x, y] = 1
pl, pt, pr, pb = plate_mask.getbbox()
inset = int((pr - pl) * 0.07)
for y in range(pt + inset, pb - inset):
    for x in range(pl + inset, pr - inset):
        c = px[x, y]
        if near(c, plate, 40):
            continue
        h, s, v = hsv(c)
        if v < 0.45 or s < 0.25:
            continue
        hue = h * 360
        if hue < 232:
            lp[x, y] = 1
        else:
            bp[x, y] = 1
from PIL import ImageFilter


def opened(mask):
    g = mask.convert("L").filter(ImageFilter.MinFilter(7)).filter(ImageFilter.MaxFilter(7))
    return g.point(lambda v: 255 if v > 127 else 0).convert("1")


from PIL import ImageChops

leaf = opened(leaf)
body = opened(body)
grown = body.convert("L").filter(ImageFilter.MaxFilter(11))
union = ImageChops.lighter(body.convert("L"), leaf.convert("L"))
body = ImageChops.darker(grown, union).point(lambda v: 255 if v > 127 else 0).convert("1")
leaf.save(out / "leaf.pbm")
body.save(out / "body.pbm")


def trace(name):
    svg = out / f"{name}.svg"
    subprocess.run(["potrace", "-s", "--invert", "--turdsize", "30", "--alphamax", "1.0", "--opttolerance", "0.25", "-o", str(svg), str(out / f"{name}.pbm")], check=True)
    text = svg.read_text()
    m = re.search(r'translate\(([-\d.]+),([-\d.]+)\) scale\(([-\d.]+),([-\d.]+)\)', text)
    tx, ty, sx, sy = (float(v) for v in m.groups())
    paths = re.findall(r'<path d="([^"]+)"', text)
    return tx, ty, sx, sy, " ".join(paths)


def bbox_of(masks):
    xs, ys = [], []
    for mask in masks:
        b = mask.getbbox()
        xs += [b[0], b[2]]
        ys += [b[1], b[3]]
    return min(xs), min(ys), max(xs), max(ys)


bx0, by0, bx1, by1 = bbox_of([leaf, body])
span = max(bx1 - bx0, by1 - by0)
target = float(sys.argv[3]) if len(sys.argv) > 3 else 64.0
k = target / span
cx, cy = (bx0 + bx1) / 2, (by0 + by1) / 2


def convert(tx, ty, sx, sy, d):
    tokens = re.findall(r'[MmCcLlZz]|-?\d+\.?\d*', d)
    i = 0
    cmd = None
    outp = []
    curx = cury = 0.0

    def absx(x):
        return (tx + sx * x - cx) * k + 54

    def absy(y):
        return (ty + sy * y - cy) * k + 54

    while i < len(tokens):
        t = tokens[i]
        if t in "MmCcLlZz":
            cmd = t
            i += 1
            if cmd in "Zz":
                outp.append("Z")
            continue
        if cmd == "M":
            x, y = float(tokens[i]), float(tokens[i + 1])
            curx, cury = x, y
            outp.append(f"M{absx(x):.2f} {absy(y):.2f}")
            i += 2
            cmd = "L"
        elif cmd == "m":
            x, y = curx + float(tokens[i]), cury + float(tokens[i + 1])
            curx, cury = x, y
            outp.append(f"M{absx(x):.2f} {absy(y):.2f}")
            i += 2
            cmd = "l"
        elif cmd == "L":
            x, y = float(tokens[i]), float(tokens[i + 1])
            curx, cury = x, y
            outp.append(f"L{absx(x):.2f} {absy(y):.2f}")
            i += 2
        elif cmd == "l":
            x, y = curx + float(tokens[i]), cury + float(tokens[i + 1])
            curx, cury = x, y
            outp.append(f"L{absx(x):.2f} {absy(y):.2f}")
            i += 2
        elif cmd == "C":
            pts = [float(v) for v in tokens[i:i + 6]]
            outp.append("C" + " ".join(f"{absx(pts[j]):.2f} {absy(pts[j + 1]):.2f}" for j in range(0, 6, 2)))
            curx, cury = pts[4], pts[5]
            i += 6
        elif cmd == "c":
            pts = [float(v) for v in tokens[i:i + 6]]
            absn = [(curx + pts[j], cury + pts[j + 1]) for j in range(0, 6, 2)]
            outp.append("C" + " ".join(f"{absx(x):.2f} {absy(y):.2f}" for x, y in absn))
            curx, cury = absn[2]
            i += 6
        else:
            i += 1
    return "".join(outp)


result = {}
for name in ("leaf", "body"):
    tx, ty, sx, sy, d = trace(name)
    result[name] = convert(tx, ty, sx, sy, d)


def sample(mask, frac_y):
    b = mask.getbbox()
    yc = int(b[1] + (b[3] - b[1]) * frac_y)
    band = max(2, (b[3] - b[1]) // 40)
    mp = mask.load()
    cols = [px[x, y] for y in range(max(b[1], yc - band), min(b[3], yc + band)) for x in range(b[0], b[2]) if mp[x, y]]
    if not cols:
        return None
    r = sum(c[0] for c in cols) // len(cols)
    g = sum(c[1] for c in cols) // len(cols)
    bl = sum(c[2] for c in cols) // len(cols)
    return "#%02x%02x%02x" % (r, g, bl)


result["colors"] = {
    "plate": "#%02x%02x%02x" % plate,
    "leaf_top": sample(leaf, 0.08),
    "leaf_bottom": sample(leaf, 0.9),
    "body_top": sample(body, 0.08),
    "body_bottom": sample(body, 0.85),
}
result["bbox_px"] = [bx0, by0, bx1, by1]
(out / "glyph.json").write_text(json.dumps(result, indent=1))
preview = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 108 108" width="432" height="432">
<defs><linearGradient id="l" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{result['colors']['leaf_top']}"/><stop offset="1" stop-color="{result['colors']['leaf_bottom']}"/></linearGradient>
<linearGradient id="b" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{result['colors']['body_top']}"/><stop offset="1" stop-color="{result['colors']['body_bottom']}"/></linearGradient></defs>
<rect width="108" height="108" fill="{result['colors']['plate']}"/><circle cx="54" cy="54" r="33" fill="none" stroke="#ffffff" stroke-opacity=".15" stroke-width=".5"/>
<path d="{result['body']}" fill="url(#b)"/><path d="{result['leaf']}" fill="url(#l)"/></svg>'''
(out / "preview.svg").write_text(preview)
print(json.dumps({"colors": result["colors"], "bbox": result["bbox_px"], "leaf_len": len(result["leaf"]), "body_len": len(result["body"])}))
