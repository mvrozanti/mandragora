set -euo pipefail

KINDLE_HOST="${KINDLE_HOST:-100.80.53.92}"
KINDLE_PORT="${KINDLE_PORT:-22}"
SRC="${WALLPAPER_DIR:-$HOME/Pictures/wllpps}"
COUNT="${1:-12}"
W=1236
H=1648
REMOTE=/mnt/us/mandragora/art
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/kindle-art"

command -v magick >/dev/null || { echo "kindle-art: imagemagick not found" >&2; exit 1; }
[ -d "$SRC" ] || { echo "kindle-art: no wallpaper dir at $SRC" >&2; exit 1; }

mkdir -p "$CACHE"
rm -f "$CACHE"/*.png

echo "kindle-art: picking $COUNT portrait-friendly wallpapers from $SRC"
mapfile -t picks < <(
  find "$SRC" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
    | shuf -n "$((COUNT * 3))"
)

made=0
for f in "${picks[@]}"; do
  [ "$made" -ge "$COUNT" ] && break
  out="$CACHE/$(printf '%02d' "$made")-$(basename "${f%.*}").png"
  # cover-crop to the panel, grayscale, gentle contrast, Floyd-Steinberg to 16 levels
  if magick "$f" \
      -auto-orient \
      -resize "${W}x${H}^" -gravity center -extent "${W}x${H}" \
      -colorspace Gray \
      -sigmoidal-contrast 3,50% \
      -dither FloydSteinberg -colors 16 \
      -strip "$out" 2>/dev/null; then
    made=$((made + 1))
  else
    rm -f "$out"
  fi
done

[ "$made" -gt 0 ] || { echo "kindle-art: nothing converted" >&2; exit 1; }
echo "kindle-art: converted $made images ($(du -sh "$CACHE" | cut -f1))"

echo "kindle-art: syncing to $KINDLE_HOST:$REMOTE"
ssh -p "$KINDLE_PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
  "root@$KINDLE_HOST" "mkdir -p $REMOTE && rm -f $REMOTE/*.png"
for f in "$CACHE"/*.png; do
  ssh -p "$KINDLE_PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
    "root@$KINDLE_HOST" "cat > $REMOTE/$(basename "$f")" < "$f"
  printf '.'
done
echo
ssh -p "$KINDLE_PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
  "root@$KINDLE_HOST" "ls $REMOTE | wc -l | tr -d '\n'; echo ' images on device'"
