#!/usr/bin/env python3
import argparse
import json
import sys

from PIL import Image, ImageDraw, ImageFont

WIDTH = 1272
HEIGHT = 1696
MARGIN = 54
BLACK = 0
WHITE = 255
INK_DIM = 96
INK_FAINT = 170


def load_font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except OSError:
        return ImageFont.load_default()


class Fonts:
    def __init__(self, heavy, bold, regular, light):
        self.heavy = heavy
        self.bold = bold
        self.regular = regular
        self.light = light

    def h(self, size):
        return load_font(self.heavy, size)

    def b(self, size):
        return load_font(self.bold, size)

    def r(self, size):
        return load_font(self.regular, size)

    def l(self, size):
        return load_font(self.light, size)


def text_w(draw, text, font):
    box = draw.textbbox((0, 0), text, font=font)
    return box[2] - box[0]


def text_h(draw, text, font):
    box = draw.textbbox((0, 0), text, font=font)
    return box[3] - box[1]


def tracked_text(draw, xy, text, font, fill, tracking=0):
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=font, fill=fill)
        x += text_w(draw, ch, font) + tracking
    return x


def tracked_w(draw, text, font, tracking=0):
    if not text:
        return 0
    total = 0
    for ch in text:
        total += text_w(draw, ch, font) + tracking
    return total - tracking


def draw_status_tag(draw, fonts, right_x, y, up):
    label = "ONLINE" if up else "OFFLINE"
    font = fonts.b(26)
    pad_x, pad_y = 22, 12
    w = text_w(draw, label, font) + pad_x * 2
    h = text_h(draw, "ONLINE", font) + pad_y * 2
    x0 = right_x - w
    y0 = y
    if up:
        draw.rectangle([x0, y0, x0 + w, y0 + h], fill=BLACK)
        tw = text_w(draw, label, font)
        draw.text(
            (x0 + (w - tw) / 2, y0 + pad_y - 3), label, font=font, fill=WHITE
        )
    else:
        draw.rectangle([x0, y0, x0 + w, y0 + h], outline=BLACK, width=3)
        tw = text_w(draw, label, font)
        draw.text(
            (x0 + (w - tw) / 2, y0 + pad_y - 3), label, font=font, fill=BLACK
        )
    return x0, y0 + h


def draw_dot(draw, cx, cy, r, filled):
    bbox = [cx - r, cy - r, cx + r, cy + r]
    if filled:
        draw.ellipse(bbox, fill=BLACK)
    else:
        draw.ellipse(bbox, outline=BLACK, width=3)


def fit_font(draw, text, loader, base_size, max_width, min_size):
    size = base_size
    while size > min_size:
        font = loader(size)
        if text_w(draw, text, font) <= max_width:
            return font
        size -= 4
    return loader(min_size)


def draw_bar(draw, x0, y0, w, h, frac):
    frac = max(0.0, min(1.0, frac))
    draw.rectangle([x0, y0, x0 + w, y0 + h], outline=BLACK, width=3)
    fill_w = int(w * frac)
    if fill_w > 4:
        draw.rectangle([x0 + 2, y0 + 2, x0 + max(fill_w - 2, 4), y0 + h - 2], fill=BLACK)


def draw_tile(draw, fonts, x, y, w, tile):
    label = tile.get("label", "").upper()
    value = tile.get("value", "")
    sub = tile.get("sub")
    bar = tile.get("bar")

    lf = fit_font(draw, label, fonts.b, 28, w, 18)
    draw.text((x, y), label, font=lf, fill=INK_DIM)
    vy = y + 44
    vf = fit_font(draw, value, fonts.h, 92, w, 48)
    draw.text((x, vy), value, font=vf, fill=BLACK)
    vh = text_h(draw, "0", vf)
    next_y = vy + vh + 18

    if sub:
        sf = fonts.r(28)
        draw.text((x, next_y), sub, font=sf, fill=INK_DIM)
        next_y += text_h(draw, sub, sf) + 16

    if bar is not None:
        draw_bar(draw, x, next_y, w, 22, bar)
        next_y += 22 + 10

    return next_y


def draw_host_panel(draw, fonts, x0, y0, x1, y1, host):
    draw.rectangle([x0, y0, x1, y1], outline=BLACK, width=3)
    pad = 34
    ix0 = x0 + pad
    ix1 = x1 - pad
    iy = y0 + pad

    up = bool(host.get("up"))
    draw_dot(draw, ix0 + 17, iy + 32, 17, up)

    name_font = fonts.b(56)
    draw.text((ix0 + 52, iy), host.get("label", "").upper(), font=name_font, fill=BLACK)

    detail = host.get("detail")
    name_h = text_h(draw, "A", name_font)
    if detail:
        df = fonts.r(27)
        draw.text((ix0 + 52, iy + name_h + 14), detail, font=df, fill=INK_DIM)

    draw_status_tag(draw, fonts, ix1, iy - 4, up)

    metrics = host.get("metrics", [])
    row_y = iy + name_h + 68
    n = len(metrics)
    if n:
        col_w = (ix1 - ix0) / n
        for i, m in enumerate(metrics):
            draw_tile(draw, fonts, ix0 + i * col_w, row_y, col_w - 44, m)

    services = host.get("services")
    if services:
        sy = y1 - pad - 34
        sf = fonts.r(27)
        sx = ix0
        for svc in services:
            on = bool(svc.get("up"))
            draw_dot(draw, sx + 9, sy + 15, 9, on)
            label = svc.get("label", "")
            draw.text((sx + 27, sy), label, font=sf, fill=BLACK if on else INK_FAINT)
            sx += 27 + text_w(draw, label, sf) + 44


def draw_node_glyph(draw, cx, cy, scale):
    r = 9 * scale
    pts = [
        (cx, cy - 34 * scale),
        (cx - 34 * scale, cy + 22 * scale),
        (cx + 34 * scale, cy + 22 * scale),
    ]
    for i in range(3):
        for j in range(i + 1, 3):
            draw.line([pts[i], pts[j]], fill=BLACK, width=4)
    for p in pts:
        draw.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=WHITE, outline=BLACK, width=4)
        draw.ellipse([p[0] - r / 2.4, p[1] - r / 2.4, p[0] + r / 2.4, p[1] + r / 2.4], fill=BLACK)


def render(data, fonts, out_path):
    img = Image.new("L", (WIDTH, HEIGHT), WHITE)
    draw = ImageDraw.Draw(img)

    x0 = MARGIN
    x1 = WIDTH - MARGIN
    y = 58

    draw.text((x0, y), "MANDRAGORA", font=fonts.h(86), fill=BLACK)
    title_h = text_h(draw, "MANDRAGORA", fonts.h(86))
    sub_y = y + title_h + 14
    tracked_text(draw, (x0, sub_y), "E - I N K   D A S H B O A R D", fonts.r(26), INK_DIM, tracking=2)

    date_str = data.get("date", "")
    time_str = data.get("time", "")
    df = fonts.b(26)
    tf = fonts.h(66)
    dw = tracked_w(draw, date_str, df, tracking=3)
    tracked_text(draw, (x1 - dw, y + 4), date_str, df, INK_DIM, tracking=3)
    tw = text_w(draw, time_str, tf)
    draw.text((x1 - tw, y + 34), time_str, font=tf, fill=BLACK)

    draw_node_glyph(draw, x1 - dw / 2, y + title_h + 55, 1.0)

    header_bottom = max(sub_y + text_h(draw, "A", fonts.r(26)), y + title_h + 55 + 45) + 26
    draw.rectangle([x0, header_bottom, x1, header_bottom + 6], fill=BLACK)

    top = header_bottom + 34
    footer_h = 74
    bottom = HEIGHT - MARGIN - footer_h
    hosts = data.get("hosts", [])
    n = len(hosts)
    gap = 26
    panel_h = (bottom - top - gap * (n - 1)) / n if n else 0

    for i, host in enumerate(hosts):
        py0 = top + i * (panel_h + gap)
        py1 = py0 + panel_h
        draw_host_panel(draw, fonts, x0, py0, x1, py1, host)

    fy0 = HEIGHT - MARGIN - footer_h
    draw.rectangle([x0, fy0, x1, fy0 + 6], fill=BLACK)
    fy = fy0 + 22
    tag = data.get("footer", "")
    tracked_text(draw, (x0, fy), tag, fonts.r(24), INK_DIM, tracking=1)
    gen = data.get("generated", "")
    gw = text_w(draw, gen, fonts.r(24))
    draw.text((x1 - gw, fy), gen, font=fonts.r(24), fill=INK_DIM)

    img.save(out_path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default="-")
    ap.add_argument("--out", required=True)
    ap.add_argument("--font-heavy", required=True)
    ap.add_argument("--font-bold", required=True)
    ap.add_argument("--font-regular", required=True)
    ap.add_argument("--font-light", required=True)
    args = ap.parse_args()

    raw = sys.stdin.read() if args.data == "-" else open(args.data, encoding="utf-8").read()
    data = json.loads(raw)
    fonts = Fonts(args.font_heavy, args.font_bold, args.font_regular, args.font_light)
    render(data, fonts, args.out)


if __name__ == "__main__":
    main()
