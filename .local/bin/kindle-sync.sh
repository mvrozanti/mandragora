#!/usr/bin/env bash
set -euo pipefail

KINDLE_HOST="${KINDLE_HOST:-100.80.53.92}"
KINDLE_PORT="${KINDLE_PORT:-22}"
LIBRARY="${KINDLE_LIBRARY:-$HOME/Documents/library/books}"
WALLPAPERS="${WALLPAPER_DIR:-$HOME/Pictures/wllpps}"
REMOTE_BOOKS=/mnt/us/documents/library/books
MIN_FREE_MB="${KINDLE_MIN_FREE_MB:-500}"

SSH=(ssh -p "$KINDLE_PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new
     -o ConnectTimeout=10 -o ServerAliveInterval=15 "root@$KINDLE_HOST")

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

log() { printf '%s kindle-sync: %s\n' "$(date +%H:%M:%S)" "$*"; }

reachable() {
  "${SSH[@]}" true 2>/dev/null
}

free_mb() {
  "${SSH[@]}" "df -m /mnt/us | tail -1 | awk '{print \$4}'" 2>/dev/null || echo 0
}

remote_manifest() {
  "${SSH[@]}" "cd '$1' 2>/dev/null || exit 0
    find . -type f 2>/dev/null | while IFS= read -r f; do
      printf '%s\t%s\n' \"\$(stat -c %s \"\$f\" 2>/dev/null)\" \"\${f#./}\"
    done" 2>/dev/null | sort -t"$(printf '\t')" -k2
}

local_manifest() {
  ( cd "$1" && find . -type f 2>/dev/null | while IFS= read -r f; do
      printf '%s\t%s\n' "$(stat -c %s "$f")" "${f#./}"
    done ) | sort -t"$(printf '\t')" -k2
}

sync_books() {
  [ -d "$LIBRARY" ] || { log "no library at $LIBRARY"; return 0; }

  local want="$WORK/want" have="$WORK/have" pending="$WORK/pending"

  local_manifest "$LIBRARY" > "$want"
  remote_manifest "$REMOTE_BOOKS" > "$have"

  comm -23 "$want" "$have" | cut -f2- > "$pending"
  local n
  n=$(wc -l < "$pending")
  if [ "$n" -eq 0 ]; then
    log "books already in sync ($(wc -l < "$want") files)"
    return 0
  fi

  local need free
  need=$(cd "$LIBRARY" && tr '\n' '\0' < "$pending" | du -c --files0-from=- 2>/dev/null | tail -1 | cut -f1)
  need=$(( (need + 1023) / 1024 ))
  free=$(free_mb)
  if [ "$free" -lt $(( need + MIN_FREE_MB )) ]; then
    log "refusing: need ${need}MB + ${MIN_FREE_MB}MB headroom, device has ${free}MB free"
    return 1
  fi

  log "pushing $n book(s), ${need}MB"
  tar cf - -C "$LIBRARY" --verbatim-files-from --files-from="$pending" \
    | "${SSH[@]}" "mkdir -p '$REMOTE_BOOKS' && tar xf - -C '$REMOTE_BOOKS'"
  log "books done"
}

sync_art() {
  [ -d "$WALLPAPERS" ] || { log "no wallpaper dir at $WALLPAPERS"; return 0; }
  if ! command -v kindle-art >/dev/null 2>&1; then
    log "kindle-art not on PATH, skipping wallpapers"
    return 0
  fi
  log "delegating wallpapers to kindle-art"
  kindle-art all
}

main() {
  if ! reachable; then
    log "device unreachable, nothing to do"
    exit 0
  fi
  case "${1:-all}" in
    books) sync_books ;;
    art)   sync_art ;;
    all)   sync_books; sync_art ;;
    *)     echo "usage: kindle-sync [books|art|all]" >&2; exit 2 ;;
  esac
}

main "$@"
