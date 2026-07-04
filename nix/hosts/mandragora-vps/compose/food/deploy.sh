#!/usr/bin/env bash
set -euo pipefail

STACK="$(cd "$(dirname "$0")" && pwd)"
REMOTE="${REMOTE:-opc@100.84.78.83}"
REMOTE_DIR="${REMOTE_DIR:-/home/opc/food}"

echo "→ provisioning $REMOTE:$REMOTE_DIR"
ssh "$REMOTE" "mkdir -p $REMOTE_DIR/data"

echo "→ rsyncing stack to $REMOTE:$REMOTE_DIR/"
rsync -av --delete \
  --exclude='/data/' \
  --exclude='.env' \
  "$STACK/" "$REMOTE:$REMOTE_DIR/"

echo "→ building + starting"
ssh "$REMOTE" "cd $REMOTE_DIR && docker compose up -d --build"

echo "→ done. https://food.mvr.ac (behind authelia)"
