#!/usr/bin/env bash
set -euo pipefail

KINDLE_HOST="${KINDLE_HOST:-100.80.53.92}"
KINDLE_PORT="${KINDLE_PORT:-22}"
SRC="${WALLPAPER_DIR:-$HOME/Pictures/wllpps}"
W=1272
H=1696
REMOTE=/mnt/us/mandragora/art
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/kindle-art"
JOBS="${KINDLE_ART_JOBS:-$(nproc)}"

usage() {
  cat >&2 <<USAGE
usage: kindle-art [N|all]     convert N wallpapers (default: all) and sync
       kindle-art --reset     wipe the device's art and the local cache first

  source:  \$WALLPAPER_DIR   ($SRC)
  device:  root@\$KINDLE_HOST:$REMOTE
Conversion is cached and the sync is incremental, so re-runs only do new work.
USAGE
  exit 1
}

RESET=0
LIMIT=all
for a in "$@"; do
  case "$a" in
    --reset) RESET=1 ;;
    all) LIMIT=all ;;
    ''|*[!0-9]*) usage ;;
    *) LIMIT="$a" ;;
  esac
done

command -v magick >/dev/null || { echo "kindle-art: imagemagick not found" >&2; exit 1; }
[ -d "$SRC" ] || { echo "kindle-art: no wallpaper dir at $SRC" >&2; exit 1; }

SSH=(ssh -p "$KINDLE_PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20 "root@$KINDLE_HOST")

mkdir -p "$CACHE"
if [ "$RESET" = 1 ]; then
  echo "kindle-art: reset — clearing local cache and device art"
  rm -f "$CACHE"/*.png
  "${SSH[@]}" "rm -f $REMOTE/*.png"
fi

mapfile -t sources < <(
  find "$SRC" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.bmp' \) \
    | sort
)
[ "${#sources[@]}" -gt 0 ] || { echo "kindle-art: no images in $SRC" >&2; exit 1; }
[ "$LIMIT" = all ] || sources=("${sources[@]:0:$LIMIT}")
echo "kindle-art: ${#sources[@]} source images in $SRC"

# Stable output name: sanitised basename + short hash of the full path, so two
# wallpapers with the same basename never collide and names are reproducible
# across runs (which is what makes the cache and the sync incremental).
outname() {
  local base hash
  base=$(basename "${1%.*}" | tr -cs 'A-Za-z0-9._-' '-' | sed 's/^-*//; s/-*$//' | cut -c1-48)
  hash=$(printf '%s' "$1" | cksum | cut -d' ' -f1)
  printf '%s-%s.png' "${base:-art}" "$hash"
}

echo "kindle-art: converting (missing only, $JOBS jobs)"
todo=0
: > "$CACHE/.worklist"
for f in "${sources[@]}"; do
  out="$CACHE/$(outname "$f")"
  [ -s "$out" ] && continue
  printf '%s\t%s\n' "$f" "$out" >> "$CACHE/.worklist"
  todo=$((todo + 1))
done

if [ "$todo" -gt 0 ]; then
  # cover-crop to the panel, greyscale, gentle contrast, Floyd-Steinberg to the
  # 16 levels the panel actually has.
  < "$CACHE/.worklist" xargs -P "$JOBS" -I{} -d '\n' bash -c '
    IFS=$(printf "\t"); set -- $1; src=$1; dst=$2
    magick "$src" -auto-orient -resize "'"$W"'x'"$H"'^" -gravity center -extent "'"$W"'x'"$H"'" \
      -colorspace Gray -sigmoidal-contrast 3,50% -dither FloydSteinberg -colors 16 \
      -define png:compression-level=9 -strip "$dst" 2>/dev/null || rm -f "$dst"
  ' _ {}
  echo "kindle-art: converted $todo new ($(ls "$CACHE"/*.png 2>/dev/null | wc -l) cached, $(du -sh "$CACHE" | cut -f1))"
else
  echo "kindle-art: nothing new to convert ($(ls "$CACHE"/*.png 2>/dev/null | wc -l) cached)"
fi
rm -f "$CACHE/.worklist"

echo "kindle-art: comparing with device"
"${SSH[@]}" "mkdir -p $REMOTE"
"${SSH[@]}" "ls $REMOTE 2>/dev/null" | sort > "$CACHE/.remote" || : > "$CACHE/.remote"
(cd "$CACHE" && ls ./*.png 2>/dev/null | sed 's|^\./||' | sort) > "$CACHE/.local"
mapfile -t missing < <(comm -23 "$CACHE/.local" "$CACHE/.remote")
rm -f "$CACHE/.local" "$CACHE/.remote"

if [ "${#missing[@]}" -eq 0 ]; then
  echo "kindle-art: device already has every image"
else
  bytes=$(cd "$CACHE" && du -cb "${missing[@]}" | tail -1 | cut -f1)
  echo "kindle-art: sending ${#missing[@]} images ($((bytes / 1024 / 1024)) MB) as one stream"
  tar -C "$CACHE" -cf - "${missing[@]}" | "${SSH[@]}" "tar -C $REMOTE -xf -"
fi

"${SSH[@]}" "printf 'kindle-art: %s images on device (%s)\n' \"\$(ls $REMOTE/*.png 2>/dev/null | wc -l | tr -d ' ')\" \"\$(du -sh $REMOTE | cut -f1)\""
