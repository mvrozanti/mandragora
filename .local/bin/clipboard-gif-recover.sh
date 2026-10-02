#!/usr/bin/env bash
html=$(cat)
url=$(printf '%s' "$html" | python3 -c '
import sys, re, html as h
m = re.search(r"<img[^>]*src=\"([^\"]+)\"", sys.stdin.read(), re.I)
if not m:
    raise SystemExit(0)
u = h.unescape(m.group(1))
if u.startswith("//"):
    u = "https:" + u
if not re.match(r"^https?://", u) or not re.search(r"\.(gif|webp|apng)(?:[?#]|$)", u, re.I):
    raise SystemExit(0)
print(u)
')
[ -z "$url" ] && exit 0

(
  dir=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/clipboard-gif-recover
  mkdir -p "$dir"
  find "$dir" -type f -mmin +60 -delete 2>/dev/null
  ts=$(date +%s%N)
  raw="$dir/$ts.raw"
  curl -fsSL --max-time 15 -A "Mozilla/5.0" -o "$raw" "$url" || { rm -f "$raw"; exit 0; }
  ext=gif
  case "$(file --mime-type -b "$raw" | cut -d';' -f1)" in
    image/webp) ext=webp ;;
    image/gif) ext=gif ;;
    *) rm -f "$raw"; exit 0 ;;
  esac
  out="$dir/$ts.$ext"
  mv "$raw" "$out"
  uri=$(python3 -c 'import sys,urllib.parse;print("file://"+urllib.parse.quote(sys.argv[1],safe="/"))' "$out")
  printf '%s\n' "$uri" | wl-copy --type text/uri-list
) &
