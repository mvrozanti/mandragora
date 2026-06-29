#!/usr/bin/env bash
# Deploy cv.mvr.ac: build the six CV PDFs from the cv repo, stage them into
# static/ under download-friendly names, then rsync static/ + the compose
# file to the VPS slot and bring the nginx container up.
#
# PDFs are not tracked (static/.gitignore); the cv repo is the source.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CV_REPO="${CV_REPO:-$HOME/Projects/cv}"
REMOTE="${REMOTE:-opc@100.84.78.83}"
REMOTE_DIR="${REMOTE_DIR:-/home/opc/cv}"

echo "→ building CVs in $CV_REPO"
make -C "$CV_REPO" all

echo "→ staging PDFs into $HERE/static"
declare -A MAP=(
  [en-original]=marcelo-vironda-rozanti-en-original.pdf
  [en-human]=marcelo-vironda-rozanti-en-impact.pdf
  [en-bot]=marcelo-vironda-rozanti-en-ats.pdf
  [ptbr-original]=marcelo-vironda-rozanti-pt-original.pdf
  [ptbr-human]=marcelo-vironda-rozanti-pt-impact.pdf
  [ptbr-bot]=marcelo-vironda-rozanti-pt-ats.pdf
)
for id in "${!MAP[@]}"; do
  cp "$CV_REPO/build/$id.pdf" "$HERE/static/${MAP[$id]}"
done

echo "→ rsyncing compose + static to $REMOTE:$REMOTE_DIR/"
ssh "$REMOTE" "mkdir -p $REMOTE_DIR/static"
rsync -av "$HERE/docker-compose.yml" "$REMOTE:$REMOTE_DIR/"
rsync -av --delete "$HERE/static/" "$REMOTE:$REMOTE_DIR/static/"

echo "→ bringing up the container"
ssh "$REMOTE" "cd $REMOTE_DIR && docker compose up -d"

echo "→ done. https://cv.mvr.ac"
