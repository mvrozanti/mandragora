#!/usr/bin/env bash
set -euo pipefail

VIZ_OUT="${VIZ_OUT:-$HOME/Music/.viz/out}"
REMOTE="${REMOTE:-opc@mandragora-vps}"
REMOTE_DIR="${REMOTE_DIR:-/home/opc/music}"

ssh "$REMOTE" mkdir -p "$REMOTE_DIR/static/tracks" "$REMOTE_DIR/static/audio"

if [ "$#" -gt 0 ]; then
  for slug in "$@"; do
    rsync -av "$VIZ_OUT/tracks/$slug/" "$REMOTE:$REMOTE_DIR/static/tracks/$slug/"
    rsync -av "$VIZ_OUT/audio/$slug.mp3" "$REMOTE:$REMOTE_DIR/static/audio/$slug.mp3"
  done
  rsync -av "$VIZ_OUT/tracks/manifest.json" "$REMOTE:$REMOTE_DIR/static/tracks/manifest.json"
else
  rsync -av "$VIZ_OUT/tracks/" "$REMOTE:$REMOTE_DIR/static/tracks/"
  rsync -av "$VIZ_OUT/audio/" "$REMOTE:$REMOTE_DIR/static/audio/"
fi
