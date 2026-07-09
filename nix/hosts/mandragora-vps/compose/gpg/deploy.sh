#!/usr/bin/env bash
# Deploy gpg.mvr.ac (public PGP key, served as text/plain) to the VPS.
# Pushes the compose file, nginx conf, and static/ into /home/opc/gpg/
# then brings the stack up.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REMOTE="${REMOTE:-opc@100.84.78.83}"
REMOTE_DIR="${REMOTE_DIR:-/home/opc/gpg}"

echo "→ ensuring $REMOTE:$REMOTE_DIR exists"
ssh "$REMOTE" "mkdir -p $REMOTE_DIR/static"

echo "→ rsyncing stack to $REMOTE:$REMOTE_DIR/"
rsync -av --delete \
  "$HERE/docker-compose.yml" \
  "$HERE/nginx.conf" \
  "$REMOTE:$REMOTE_DIR/"
rsync -av --delete "$HERE/static/" "$REMOTE:$REMOTE_DIR/static/"

echo "→ bringing stack up"
ssh "$REMOTE" "cd $REMOTE_DIR && docker compose up -d"

echo "→ done. https://gpg.mvr.ac serves the pub key as text/plain."
