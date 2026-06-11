#!/usr/bin/env bash
# Deploy music.mvr.ac static site to the VPS.
#
# The static dir lives in this compose folder and is rsynced to
# /home/opc/music/static/ on the VPS. Before rsync we refresh the
# emotion-tagging data files from the canonical desktop location:
#   /home/m/Music/.emotion/{scores.csv, ranked.tsv}
# into ./static/data/. Those files are gitignored — the canonical
# source is the desktop's ~/Music/.emotion/ cache.
set -euo pipefail

REPO_STATIC="$(cd "$(dirname "$0")/static" && pwd)"
DATA_DIR="$REPO_STATIC/data"
EMOTION_DIR="${EMOTION_DIR:-/home/m/Music/.emotion}"
REMOTE="${REMOTE:-opc@100.84.78.83}"
REMOTE_DIR="${REMOTE_DIR:-/home/opc/music/static}"

mkdir -p "$DATA_DIR"

if [[ -f "$EMOTION_DIR/scores.csv" ]]; then
    cp "$EMOTION_DIR/scores.csv" "$DATA_DIR/scores.csv"
    echo "→ copied scores.csv ($(wc -l <"$DATA_DIR/scores.csv") lines)"
else
    echo "WARN: $EMOTION_DIR/scores.csv missing — page will be empty" >&2
fi
if [[ -f "$EMOTION_DIR/ranked.tsv" ]]; then
    cp "$EMOTION_DIR/ranked.tsv" "$DATA_DIR/ranked.tsv"
fi

echo "→ rsyncing $REPO_STATIC/ to $REMOTE:$REMOTE_DIR/"
ssh "$REMOTE" "mkdir -p $REMOTE_DIR"
rsync -av --delete "$REPO_STATIC/" "$REMOTE:$REMOTE_DIR/"

echo "→ done. nginx serves new files immediately (no container restart)."
