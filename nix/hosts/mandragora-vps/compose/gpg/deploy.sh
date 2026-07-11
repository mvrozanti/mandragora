#!/usr/bin/env bash
# Deploy gpg.mvr.ac to the VPS.
# Serves the public PGP key (text/plain to curl, HTML page to browsers),
# a client-side-encrypted public inbox, and an Authelia-gated reader.
# Pushes the compose file + app/ into /home/opc/gpg/ and rebuilds the image.
# Compose-only — no nixos rebuild required.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REMOTE="${REMOTE:-opc@100.84.78.83}"
REMOTE_DIR="${REMOTE_DIR:-/home/opc/gpg}"

echo "→ ensuring $REMOTE:$REMOTE_DIR exists"
ssh "$REMOTE" "mkdir -p $REMOTE_DIR/app $REMOTE_DIR/data"

echo "→ rsyncing stack to $REMOTE:$REMOTE_DIR/"
rsync -av "$HERE/docker-compose.yml" "$REMOTE:$REMOTE_DIR/"
rsync -av --delete "$HERE/app/" "$REMOTE:$REMOTE_DIR/app/"

echo "→ building + bringing stack up"
ssh "$REMOTE" "cd $REMOTE_DIR && docker compose up -d --build"

echo "→ done. https://gpg.mvr.ac"
