#!/usr/bin/env bash

set -euo pipefail

REPO_STATIC="$(cd "$(dirname "$0")/static" && pwd)"
REMOTE="${REMOTE:-opc@100.84.78.83}"
REMOTE_DIR="${REMOTE_DIR:-/home/opc/lenia/static}"

echo "→ rsyncing $REPO_STATIC/ to $REMOTE:$REMOTE_DIR/"
rsync -av --delete "$REPO_STATIC/" "$REMOTE:$REMOTE_DIR/"

echo "→ done. nginx serves new files immediately (no container restart)."
