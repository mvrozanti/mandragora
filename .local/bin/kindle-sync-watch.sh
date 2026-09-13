#!/usr/bin/env bash
set -euo pipefail

LIBRARY="${KINDLE_LIBRARY:-$HOME/Documents/library/books}"
WALLPAPERS="${WALLPAPER_DIR:-$HOME/Pictures/wllpps}"
DEBOUNCE="${KINDLE_SYNC_DEBOUNCE:-20}"

watched=()
[ -d "$LIBRARY" ] && watched+=("$LIBRARY")
[ -d "$WALLPAPERS" ] && watched+=("$WALLPAPERS")

if [ "${#watched[@]}" -eq 0 ]; then
  echo "kindle-sync-watch: nothing to watch" >&2
  exit 0
fi

echo "kindle-sync-watch: watching ${watched[*]} (debounce ${DEBOUNCE}s)"

pending=0
while true; do
  if [ "$pending" -eq 0 ]; then
    inotifywait -r -q -e close_write -e moved_to -e delete -e move_self \
      --format '%w%f' "${watched[@]}" >/dev/null
    pending=1
    continue
  fi

  if inotifywait -r -q -t "$DEBOUNCE" -e close_write -e moved_to -e delete -e move_self \
      --format '%w%f' "${watched[@]}" >/dev/null; then
    continue
  fi

  pending=0
  echo "kindle-sync-watch: settled, syncing"
  kindle-sync all || echo "kindle-sync-watch: sync failed, will retry on next change" >&2
done
