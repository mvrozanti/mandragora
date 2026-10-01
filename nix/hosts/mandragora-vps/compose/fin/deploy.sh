#!/usr/bin/env bash
# Deploy fin.mvr.ac — sync algotrading source to VPS,
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
#   LOCAL_REPO         orderbook source     default ~/Projects/algotrading
#   FIN_DATA_DIR       paper-trade data     default /home/opc/dnl_paper
#
# Usage:
#   ./deploy.sh                first deploy or update
#   FIN_DATA_DIR=/elsewhere ./deploy.sh   override mount source

set -euo pipefail

REMOTE="${REMOTE:-opc@100.84.78.83}"
REMOTE_DIR="${REMOTE_DIR:-/home/opc/fin}"
LOCAL_REPO="${LOCAL_REPO:-$HOME/Projects/algotrading}"
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
# Local build trees never ship: webui/.pip-prefix is the 7.5 GB nix-shell pytorch
# tree and 5.4 GB of it reached the VPS on 2026-09-29 before the transfer was
# killed. The container installs its own deps from webui/Dockerfile.
rsync -av --delete \
  --exclude='__pycache__/' --exclude='*.pyc' \
  --exclude='.pip-prefix/' --exclude='.venv/' \
  --exclude='.pytest_cache/' --exclude='.mypy_cache/' --exclude='.ruff_cache/' \
  "$LOCAL_REPO/webui/" "$REMOTE:$REMOTE_DIR/src/webui/"

echo "→ rsyncing repo *.md + the inputs the six questions read"
# PARITY IS THE INVARIANT (operator, 2026-09-30): "whatever appears on the
# desktop should appear on the mobile." fin.mvr.ac is how the fund is read away
# from the machine, so a question that answers on the desktop and not here is a
# defect, not a degradation.
#
# Each include below is one question's input. Dropping one does not break the
# page — webui/questions.py returns _unanswerable() and says so honestly — it
# just makes the phone a worse mirror than the desk:
#   data/reference/*.json              the derived after-tax CDB bar (Q1). The
#                                      container ships no pandas, so it cannot
#                                      compute this from cdi.parquet itself.
#   data/signal_bank/                  the banked forecast streams (Q2, Q3)
#   data/raw/b3_intraday/coverage_*    B3 capture coverage (Q4)
#   data/decisions.jsonl               gate throughput and surprise rate (Q5)
#   algorithms/strategy_lab/results/   the candidate space (Q5)
#   algorithms/*/live/*.json|jsonl     lane-tagged iteration rows (Q5)
# ~30 MB total, all small and derived. Local BUILD trees are still excluded
# below; data artifacts are what the questions are made of.
#
# This list drifts the same way a nav bar does, so deploy.sh ends by running
# scripts/panes_parity.py, which compares the deployed question tree against
# this machine's and names any question that lost an answer in transit.
rsync -av \
  --prune-empty-dirs \
  --include='*/' --include='*.md' \
  --include='data/reference/*.json' \
  --include='data/signal_bank/**' \
  --include='data/raw/b3_intraday/coverage_summary.json' \
  --include='data/raw/b3_intraday/coverage.jsonl' \
  --include='data/decisions.jsonl' \
  --include='algorithms/strategy_lab/results/lab_decisions.jsonl' \
  --include='algorithms/*/live/*.json' \
  --include='algorithms/*/live/*.jsonl' \
  --exclude='*' \
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

echo "→ parity: does the phone see what the desk sees?"
if [[ -x "$LOCAL_REPO/scripts/panes_parity.py" ]]; then
  "$LOCAL_REPO/scripts/panes_parity.py" --remote "$REMOTE" || \
    echo "  (parity check reported a difference — see above)"
else
  echo "  (scripts/panes_parity.py absent, skipping)"
fi

echo "→ done. visit https://fin.mvr.ac (authelia-gated)."
echo "   logs:   ssh $REMOTE 'docker logs -f fin'"
echo "   status: ssh $REMOTE 'docker ps --filter name=fin'"
