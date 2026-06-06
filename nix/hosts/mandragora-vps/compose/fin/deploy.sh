#!/usr/bin/env bash
# Deploy fin.mvr.ac — sync orderbook-algotrading source to VPS,
# build the fin-mvr-ac container, and bring the stack up.
#
# Idempotent. Re-run after changes to webui/ on the desktop.
#
# Prereqs on VPS: docker, seafile-net network (created by seafile stack),
# authelia stack running.
#
# Env overrides:
#   REMOTE             ssh target           default opc@100.84.78.83
#   REMOTE_DIR         slot on VPS          default /home/opc/fin
#   LOCAL_REPO         orderbook source     default ~/Projects/orderbook-algotrading
#   FIN_DATA_DIR       paper-trade data     default /home/opc/dnl_paper
#
# Usage:
#   ./deploy.sh                first deploy or update
#   FIN_DATA_DIR=/elsewhere ./deploy.sh   override mount source

set -euo pipefail

REMOTE="${REMOTE:-opc@100.84.78.83}"
REMOTE_DIR="${REMOTE_DIR:-/home/opc/fin}"
LOCAL_REPO="${LOCAL_REPO:-$HOME/Projects/orderbook-algotrading}"
FIN_DATA_DIR="${FIN_DATA_DIR:-/home/opc/dnl_paper}"
COMPOSE_SRC="$(cd "$(dirname "$0")" && pwd)/docker-compose.yml"

if [[ ! -d "$LOCAL_REPO/webui" ]]; then
  echo "ERR: $LOCAL_REPO/webui not found (set LOCAL_REPO)" >&2
  exit 1
fi
if [[ ! -f "$COMPOSE_SRC" ]]; then
  echo "ERR: docker-compose.yml not found next to deploy.sh" >&2
  exit 1
fi

echo "→ ensuring remote slot $REMOTE:$REMOTE_DIR exists"
ssh "$REMOTE" "mkdir -p $REMOTE_DIR/src"

echo "→ rsyncing webui/ to $REMOTE:$REMOTE_DIR/src/webui/"
rsync -av --delete \
  --exclude='__pycache__/' --exclude='*.pyc' \
  "$LOCAL_REPO/webui/" "$REMOTE:$REMOTE_DIR/src/webui/"

echo "→ rsyncing all repo *.md files to $REMOTE:$REMOTE_DIR/src/ for /graph"
rsync -av \
  --prune-empty-dirs \
  --include='*/' --include='*.md' --exclude='*' \
  --exclude='.venv/' --exclude='.pip-prefix/' \
  --exclude='__pycache__/' --exclude='archived_paper_ledgers/' \
  --exclude='.claude/' --exclude='.pytest_cache/' \
  --exclude='node_modules/' \
  "$LOCAL_REPO/" "$REMOTE:$REMOTE_DIR/src/"

echo "→ rsyncing .git/ (for /api/commits) — includes pack files"
rsync -av --delete \
  --exclude='/lfs/' \
  --exclude='/logs/' \
  --exclude='/hooks/' \
  "$LOCAL_REPO/.git/" "$REMOTE:$REMOTE_DIR/src/.git/" || \
  echo "  (warn: .git rsync failed; /api/commits will be empty)"

echo "→ syncing compose.yml"
rsync -av "$COMPOSE_SRC" "$REMOTE:$REMOTE_DIR/docker-compose.yml"

if [[ -z "${AUTOPILOT_TOKEN:-}" && -r "$HOME/.config/autopilot-agent/env" ]]; then
  AUTOPILOT_TOKEN=$(grep '^AUTOPILOT_TOKEN=' "$HOME/.config/autopilot-agent/env" | cut -d= -f2-)
fi
if [[ -z "${AUTOPILOT_TOKEN:-}" ]]; then
  echo "ERR: AUTOPILOT_TOKEN not set and not readable from ~/.config/autopilot-agent/env" >&2
  echo "     run: AUTOPILOT_TOKEN=\$(python3 -c 'import secrets; print(secrets.token_hex(32))') ./deploy.sh" >&2
  exit 3
fi

AUTOPILOT_AGENT_URL="${AUTOPILOT_AGENT_URL:-http://100.115.80.79:8765}"
AUTOPILOT_ALLOWED_USERS="${AUTOPILOT_ALLOWED_USERS:-m}"

echo "→ writing .env (FIN_DATA_DIR=$FIN_DATA_DIR, FIN_SRC_DIR=$REMOTE_DIR/src, AUTOPILOT_*)"
ssh "$REMOTE" "umask 077 && cat > $REMOTE_DIR/.env <<EOF
FIN_DATA_DIR=$FIN_DATA_DIR
FIN_SRC_DIR=$REMOTE_DIR/src
FIN_IMAGE=fin-mvr-ac:latest
AUTOPILOT_AGENT_URL=$AUTOPILOT_AGENT_URL
AUTOPILOT_TOKEN=$AUTOPILOT_TOKEN
AUTOPILOT_ALLOWED_USERS=$AUTOPILOT_ALLOWED_USERS
EOF"

echo "→ verifying data dir $FIN_DATA_DIR exists on VPS"
ssh "$REMOTE" "test -d $FIN_DATA_DIR || { echo 'ERR: $FIN_DATA_DIR missing on VPS'; exit 1; }"

echo "→ building image fin-mvr-ac:latest on VPS"
ssh "$REMOTE" "cd $REMOTE_DIR && docker build -f src/webui/Dockerfile -t fin-mvr-ac:latest src/"

echo "→ docker compose up -d"
ssh "$REMOTE" "cd $REMOTE_DIR && docker compose up -d"

echo "→ waiting for healthz"
sleep 4
ssh "$REMOTE" "docker exec fin wget -qO- http://localhost:8080/healthz || echo '(healthz check failed)'"

echo "→ done. visit https://fin.mvr.ac (authelia-gated)."
echo "   logs:   ssh $REMOTE 'docker logs -f fin'"
echo "   status: ssh $REMOTE 'docker ps --filter name=fin'"
