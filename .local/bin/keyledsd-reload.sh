#!/usr/bin/env bash
set -u
src="$HOME/.cache/matugen/keyledsd.conf"
dst="$HOME/.config/keyledsd.conf"
[[ -f "$src" ]] || exit 0
mkdir -p "$(dirname "$dst")"
tmp="$(mktemp -p "$(dirname "$dst")" .keyledsd.XXXXXX)"

KEYLEDS_SAT_MULT="${KEYLEDS_SAT_MULT:-1.8}" \
KEYLEDS_VAL_MIN="${KEYLEDS_VAL_MIN:-0.85}" \
python3 - "$src" "$tmp" <<'PY'
import colorsys, os, re, sys

src, dst = sys.argv[1], sys.argv[2]
sat_mult = float(os.environ.get("KEYLEDS_SAT_MULT", "1.8"))
val_min = float(os.environ.get("KEYLEDS_VAL_MIN", "0.85"))

hex_re = re.compile(r'"([0-9a-fA-F]{6})"')

def saturate(m):
    h = m.group(1)
    r, g, b = (int(h[i:i+2], 16) / 255 for i in (0, 2, 4))
    hh, ss, vv = colorsys.rgb_to_hsv(r, g, b)
    ss = min(1.0, ss * sat_mult)
    vv = max(val_min, vv)
    r, g, b = colorsys.hsv_to_rgb(hh, ss, vv)
    return f'"{int(r*255):02x}{int(g*255):02x}{int(b*255):02x}"'

with open(src) as f:
    text = f.read()

out, in_rainbow, indent = [], False, None
for line in text.splitlines(keepends=True):
    stripped = line.lstrip(' ')
    spaces = len(line) - len(stripped)
    if stripped.startswith('rainbow:'):
        in_rainbow, indent = True, spaces
    elif in_rainbow and stripped and not stripped.startswith('#') and spaces <= indent:
        in_rainbow = False
    if in_rainbow and 'colors:' in line:
        line = hex_re.sub(saturate, line)
    out.append(line)

with open(dst, 'w') as f:
    f.write(''.join(out))
PY

chmod 644 "$tmp"
mv -f "$tmp" "$dst"
systemctl --user restart keyledsd 2>/dev/null || true
