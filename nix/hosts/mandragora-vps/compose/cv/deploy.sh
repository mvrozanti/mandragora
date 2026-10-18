#!/usr/bin/env bash
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
  [en-default]=marcelo-vironda-rozanti-en-default.pdf
  [en-bot]=marcelo-vironda-rozanti-en-ats.pdf
  [ptbr-default]=marcelo-vironda-rozanti-pt-default.pdf
  [ptbr-bot]=marcelo-vironda-rozanti-pt-ats.pdf
)
rm -f "$HERE"/static/*.pdf
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
