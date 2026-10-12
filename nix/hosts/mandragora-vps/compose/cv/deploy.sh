#!/usr/bin/env bash
# Deploy cv.mvr.ac: build the six CV PDFs from the cv repo, stage them into
# static/ under download-friendly names, then rsync static/ + the compose
# file to the VPS slot and bring the nginx container up.
#
# PDFs are not tracked (static/.gitignore); the cv repo is the source.
set -euo pipefail

# shellcheck source=/dev/null
. "$(cd "$(dirname "$0")" && pwd)/../../deploy-guard.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
CV_REPO="${CV_REPO:-$HOME/Projects/cv}"
REMOTE="${REMOTE:-opc@100.84.78.83}"
REMOTE_DIR="${REMOTE_DIR:-/home/opc/cv}"

deploy_begin cv "$HERE"

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

deploy_mkdir static
deploy_rsync "$HERE/docker-compose.yml" :
deploy_rsync "$HERE/nginx.conf" :
deploy_rsync --delete "$HERE/static/" :static/
deploy_up
deploy_end

echo "→ done. https://cv.mvr.ac"
