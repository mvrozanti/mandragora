#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

KINDLE_HOST="${KINDLE_HOST:-100.80.53.92}"
KINDLE_PORT="${KINDLE_PORT:-22}"
LIBRARY="${KINDLE_LIBRARY:-$HOME/Documents/library/kindle}"
WALLPAPERS="${WALLPAPER_DIR:-$HOME/Pictures/wllpps}"
REMOTE_BOOKS=/mnt/us/documents/library/books
NOTES="${KINDLE_NOTES:-$HOME/Documents/notes}"
REMOTE_NOTES=/mnt/us/documents/notes
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
    done" 2>/dev/null | sort
}

READABLE=( -iname '*.epub' -o -iname '*.mobi' -o -iname '*.azw3' -o -iname '*.azw'
           -o -iname '*.pdf' -o -iname '*.txt' -o -iname '*.cbz' -o -iname '*.fb2' )

local_manifest() {
  ( cd "$1" && find . -type f \( "${READABLE[@]}" \) 2>/dev/null | while IFS= read -r f; do
      printf '%s\t%s\n' "$(stat -c %s "$f")" "${f#./}"
    done ) | sort
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

prune_books() {
  local have="$WORK/phave" stale="$WORK/stale"
  remote_manifest "$REMOTE_BOOKS" | cut -f2- | sort > "$have"
  grep -viE '\.(epub|mobi|azw3|azw|pdf|txt|cbz|fb2)$' "$have" > "$stale" || true

  local n
  n=$(wc -l < "$stale")
  if [ "$n" -eq 0 ]; then
    log "nothing unreadable under $REMOTE_BOOKS"
    return 0
  fi

  log "$n file(s) under $REMOTE_BOOKS are not a format the device can open"
  sed 's/^/    /' "$stale" | head -12
  [ "$n" -gt 12 ] && log "    ... and $(( n - 12 )) more"

  if [ "$PRUNE" != "yes" ]; then
    log "dry run — pass --prune to delete them"
    log "readable files are never pruned, even if absent from $LIBRARY"
    return 0
  fi

  tr '\n' '\0' < "$stale" | "${SSH[@]}" "cd '$REMOTE_BOOKS' || exit 1
    xargs -0 rm -f --
    find . -type d -empty -delete 2>/dev/null
    exit 0"
  log "pruned $n unreadable file(s)"
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

sync_notes() {
  [ -d "$NOTES" ] || { log "no notes at $NOTES"; return 0; }

  local want="$WORK/nwant" have="$WORK/nhave" list="$WORK/nlist" stale="$WORK/nstale"

  ( cd "$NOTES" && find . -type f \( -iname '*.md' -o -iname '*.txt' \) -not -path '*/.*' \
      -printf '%s\t%T@\t%P\n' ) | sort > "$want"
  "${SSH[@]}" "cat '$REMOTE_NOTES/.manifest' 2>/dev/null" > "$have" || true

  if cmp -s "$want" "$have"; then
    log "notes already in sync ($(wc -l < "$want") files)"
    return 0
  fi

  cut -f3- "$want" | sort > "$list"
  if [ -s "$list" ]; then
    log "pushing $(wc -l < "$list") note(s)"
    tar cf - -C "$NOTES" --verbatim-files-from --files-from="$list" \
      | "${SSH[@]}" "mkdir -p '$REMOTE_NOTES' && tar xf - -C '$REMOTE_NOTES'"
  fi

  "${SSH[@]}" "cd '$REMOTE_NOTES' 2>/dev/null || exit 0
    find . -type f \( -name '*.md' -o -name '*.txt' \)" 2>/dev/null \
    | cut -c3- | sort | comm -13 "$list" - > "$stale"
  if [ -s "$stale" ]; then
    tr '\n' '\0' < "$stale" | "${SSH[@]}" "cd '$REMOTE_NOTES' || exit 1
      xargs -0 rm -f --
      find . -type d -empty -delete 2>/dev/null
      exit 0"
    log "removed $(wc -l < "$stale") note(s) that left the desktop"
  fi

  "${SSH[@]}" "mkdir -p '$REMOTE_NOTES' && cat > '$REMOTE_NOTES/.manifest'" < "$want"
  log "notes done"
}

PRUNE=no
ACTION=all
for a in "$@"; do
  case "$a" in
    --prune)     PRUNE=yes ;;
    --prune-dry) PRUNE=no ;;
    books|art|notes|all|prune) ACTION="$a" ;;
    *) echo "usage: kindle-sync [books|art|notes|all|prune] [--prune]" >&2; exit 2 ;;
  esac
done

main() {
  if ! reachable; then
    log "device unreachable, nothing to do"
    exit 0
  fi
  case "$ACTION" in
    books) sync_books ;;
    art)   sync_art ;;
    notes) sync_notes ;;
    prune) prune_books ;;
    all)   sync_books; sync_art; sync_notes ;;
  esac
}

main "$@"
