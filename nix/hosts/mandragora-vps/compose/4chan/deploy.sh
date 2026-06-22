#!/usr/bin/env bash
set -euo pipefail

PROJECT="${FOURCHAN_PROJECT:-/home/m/Projects/4chan-international-visualizer}"
REMOTE="${REMOTE:-opc@100.84.78.83}"
REMOTE_DIR="${REMOTE_DIR:-/home/opc/4chan/static}"

echo "→ building frontend in $PROJECT"
( cd "$PROJECT" && npm run build )

echo "→ rsyncing $PROJECT/dist/ to $REMOTE:$REMOTE_DIR/"
ssh "$REMOTE" "mkdir -p $REMOTE_DIR"
rsync -av --delete "$PROJECT/dist/" "$REMOTE:$REMOTE_DIR/"

echo "→ done. nginx serves new files immediately (no container restart)."
