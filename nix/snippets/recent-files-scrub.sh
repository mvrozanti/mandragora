#!/usr/bin/env bash
set -euo pipefail

XBEL="$HOME/.local/share/recently-used.xbel"
EXCL="$HOME/.config/path-exclusions"

[ -r "$XBEL" ] || exit 0
[ -r "$EXCL" ] || exit 0

mapfile -t patterns < "$EXCL"
expanded=()
for p in "${patterns[@]}"; do
  [ -z "$p" ] && continue
  case "$p" in "~"|"~/"*) p="$HOME${p#\~}" ;; esac
  expanded+=("$p")
done
[ ${#expanded[@]} -eq 0 ] && exit 0

exec python3 - "$XBEL" "${expanded[@]}" <<'PYEOF'
import sys, re, os, urllib.parse, tempfile
xbel = sys.argv[1]
patterns = [p for p in sys.argv[2:] if p]
try:
    with open(xbel) as f:
        s = f.read()
except FileNotFoundError:
    sys.exit(0)

def hit(block):
    for p in patterns:
        if p in block:
            return True
        enc = urllib.parse.quote(p, safe='')
        if enc in block:
            return True
    return False

pat = re.compile(r'  <bookmark [^>]*?>.*?</bookmark>\n', re.DOTALL)
out = []
last = 0
dropped = 0
for m in pat.finditer(s):
    if hit(m.group(0)):
        out.append(s[last:m.start()])
        dropped += 1
    else:
        out.append(s[last:m.end()])
    last = m.end()
out.append(s[last:])
new = ''.join(out)
if dropped == 0 or new == s:
    sys.exit(0)
d = os.path.dirname(xbel) or '.'
fd, tmp = tempfile.mkstemp(prefix='.recently-used.', suffix='.xbel', dir=d)
try:
    with os.fdopen(fd, 'w') as f:
        f.write(new)
    os.replace(tmp, xbel)
except Exception:
    try: os.unlink(tmp)
    except OSError: pass
    raise
PYEOF
