#!/usr/bin/env bash
# Deploy demo.mvr.ac static content to the VPS.
# Pushes static/ (the canonical source, tracked in /etc/nixos/mandragora)
# into /home/opc/demo/static/ on the VPS, preserving the vault content
# and graph.json that are written by separate vault-graph tooling.

set -euo pipefail

REPO_STATIC="$(cd "$(dirname "$0")/static" && pwd)"
REMOTE="${REMOTE:-opc@100.84.78.83}"
REMOTE_DIR="${REMOTE_DIR:-/home/opc/demo/static}"

echo "→ rsyncing $REPO_STATIC/ to $REMOTE:$REMOTE_DIR/"
rsync -av --delete \
  --exclude='/vault/' \
  --exclude='/vault-graph/' \
  --exclude='/graph.json' \
  "$REPO_STATIC/" "$REMOTE:$REMOTE_DIR/"

echo "→ done. nginx serves new files immediately (no container restart)."
