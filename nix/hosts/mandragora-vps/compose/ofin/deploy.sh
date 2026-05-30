#!/usr/bin/env bash
# Deploy ofin.mvr.ac — sync source, render .env from sops, build container,
# bring stack up. Idempotent.
#
# Pluggy client_id lives in this script (treat as moderately sensitive).
# Pluggy client_secret is pulled from sops at deploy time and is never
# echoed or logged.
#
# Env overrides:
#   REMOTE           ssh target              default opc@mandragora-vps
#   REMOTE_DIR       slot on VPS             default /home/opc/ofin
#   LOCAL_REPO       app source              default ~/Projects/ofin
#   PLUGGY_CLIENT_SECRET_FILE  override the sops-nix path
#   PLUGGY_WEBHOOK_SECRET      optional HMAC secret, blank = unverified

set -euo pipefail

REMOTE="${REMOTE:-opc@mandragora-vps}"
REMOTE_DIR="${REMOTE_DIR:-/home/opc/ofin}"
LOCAL_REPO="${LOCAL_REPO:-$HOME/Projects/ofin}"
COMPOSE_SRC="$(cd "$(dirname "$0")" && pwd)/docker-compose.yml"
PLUGGY_CLIENT_SECRET_FILE="${PLUGGY_CLIENT_SECRET_FILE:-/run/secrets/pluggy/client_secret}"

PLUGGY_CLIENT_ID="${PLUGGY_CLIENT_ID:-6563d062-2132-48de-acb2-0e0c83525275}"
PLUGGY_WEBHOOK_SECRET="${PLUGGY_WEBHOOK_SECRET:-}"

if [[ ! -d "$LOCAL_REPO/src/ofin" ]]; then
  echo "ERR: $LOCAL_REPO/src/ofin not found (set LOCAL_REPO)" >&2
  exit 1
fi
if [[ ! -f "$COMPOSE_SRC" ]]; then
  echo "ERR: docker-compose.yml not found next to deploy.sh" >&2
  exit 1
fi
if [[ ! -r "$PLUGGY_CLIENT_SECRET_FILE" ]]; then
  echo "ERR: $PLUGGY_CLIENT_SECRET_FILE not readable. Run \`sudo nixos-rebuild switch --flake /etc/nixos/mandragora#mandragora\` so sops-nix mounts pluggy/client_secret, or override with PLUGGY_CLIENT_SECRET_FILE=." >&2
  exit 1
fi

echo "→ reading pluggy client_secret from $PLUGGY_CLIENT_SECRET_FILE"
PLUGGY_CLIENT_SECRET="$(< "$PLUGGY_CLIENT_SECRET_FILE")"
if [[ -z "$PLUGGY_CLIENT_SECRET" ]]; then
  echo "ERR: pluggy/client_secret file empty" >&2
  exit 1
fi

if [[ -z "${OFIN_DB_PASSWORD:-}" ]]; then
  OFIN_DB_PASSWORD="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  echo "→ generated fresh OFIN_DB_PASSWORD (rotate by deleting /home/opc/ofin/.env)"
fi

echo "→ ensuring remote slot $REMOTE:$REMOTE_DIR exists"
ssh "$REMOTE" "mkdir -p $REMOTE_DIR/src $REMOTE_DIR/db"

echo "→ rsyncing app source to $REMOTE:$REMOTE_DIR/src/"
rsync -av --delete \
  --exclude='__pycache__/' --exclude='*.pyc' \
  --exclude='.venv/' --exclude='.git/' \
  "$LOCAL_REPO/" "$REMOTE:$REMOTE_DIR/src/"

echo "→ syncing compose.yml"
rsync -av "$COMPOSE_SRC" "$REMOTE:$REMOTE_DIR/docker-compose.yml"

echo "→ writing $REMOTE:$REMOTE_DIR/.env (mode 0600, secrets not echoed)"
ssh "$REMOTE" "umask 077 && cat > $REMOTE_DIR/.env" <<EOF
MVR_AC=mvr.ac
OFIN_IMAGE=ofin:latest
OFIN_DB_DIR=$REMOTE_DIR/db
OFIN_DB_PASSWORD=$OFIN_DB_PASSWORD
OFIN_DEFAULT_USER=m
PLUGGY_CLIENT_ID=$PLUGGY_CLIENT_ID
PLUGGY_CLIENT_SECRET=$PLUGGY_CLIENT_SECRET
PLUGGY_WEBHOOK_SECRET=$PLUGGY_WEBHOOK_SECRET
EOF

unset PLUGGY_CLIENT_SECRET OFIN_DB_PASSWORD

echo "→ building image ofin:latest on VPS"
ssh "$REMOTE" "cd $REMOTE_DIR/src && docker build -t ofin:latest ."

echo "→ docker compose up -d"
ssh "$REMOTE" "cd $REMOTE_DIR && docker compose up -d"

echo "→ waiting for healthz"
sleep 6
ssh "$REMOTE" "docker exec ofin wget -qO- http://localhost:8080/healthz || echo '(healthz check failed)'"

echo "→ done. visit https://ofin.mvr.ac (authelia-gated)."
echo "   logs:   ssh $REMOTE 'docker logs -f ofin'"
echo "   status: ssh $REMOTE 'docker ps --filter name=ofin'"
