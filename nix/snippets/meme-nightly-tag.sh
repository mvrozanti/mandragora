#!/usr/bin/env bash
deadline=$(date -d "$MEME_NIGHTLY_UNTIL" +%s)
index="${VTAG_CACHE_DIR:-$HOME/.cache/vtag}/index.sqlite"
queue="${XDG_RUNTIME_DIR:-/tmp}/meme-nightly-queue"

if (( deadline - $(date +%s) < 600 )); then
  echo "meme-nightly: less than 10 min left before $MEME_NIGHTLY_UNTIL, not starting"
  exit 0
fi

vfind --roots "$MEME_NIGHTLY_ROOTS" >/dev/null || true

IFS=: read -r -a roots <<< "$MEME_NIGHTLY_ROOTS"
where=""
for root in "${roots[@]}"; do
  escaped=${root//\'/\'\'}
  where+="${where:+ OR }substr(path, 1, length('$escaped/')) = '$escaped/'"
done
sqlite3 -readonly "$index" "SELECT path FROM images WHERE payload IS NULL AND ($where) ORDER BY mtime DESC" > "$queue"
echo "meme-nightly: $(wc -l < "$queue") untagged files queued"

if [[ -s "$queue" ]]; then
  left=$(( deadline - $(date +%s) ))
  timeout -s INT -k 120 "$left" meme tag --from-file "$queue" || echo "meme-nightly: meme tag stopped with status $?"
fi
rm -f "$queue"

vfind --roots "$MEME_NIGHTLY_ROOTS" >/dev/null || true
echo "meme-nightly: index refreshed"
