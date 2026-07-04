import sys

import fontforge
import psMat

infile, svgfile, outfile = sys.argv[1], sys.argv[2], sys.argv[3]

CODEPOINT = 0xE900
REF_CODEPOINT = 0xF0874

font = fontforge.open(infile)
glyph = font.createChar(CODEPOINT, "nvidia")
glyph.clear()
glyph.importOutlines(svgfile, ("correctdir",))
glyph.transform(psMat.scale(1, -1))
glyph.removeOverlap()

bx0, by0, bx1, by1 = glyph.boundingBox()
glyph_w, glyph_h = bx1 - bx0, by1 - by0

if REF_CODEPOINT in font:
    ref = font[REF_CODEPOINT]
    rx0, ry0, rx1, ry1 = ref.boundingBox()
else:
    rx0, ry0, rx1, ry1 = 0.0, 0.0, float(font.em), float(font.em)

box_h = ry1 - ry0
box_w = font.em * 0.95

if glyph_w > 0 and glyph_h > 0:
    glyph.transform(psMat.scale(min(box_w / glyph_w, box_h / glyph_h)))
    bx0, by0, bx1, by1 = glyph.boundingBox()

ref_cy = (ry0 + ry1) / 2.0
cur_cy = (by0 + by1) / 2.0
glyph.transform(psMat.translate(0.0, ref_cy - cur_cy))

bearing = int(font.em * 0.08)
bx0, _, bx1, _ = glyph.boundingBox()
glyph.transform(psMat.translate(bearing - bx0, 0.0))
_, _, bx1, _ = glyph.boundingBox()
glyph.width = int(bx1 + bearing)

glyph.addExtrema()
glyph.round()

font.generate(outfile)
font.close()
