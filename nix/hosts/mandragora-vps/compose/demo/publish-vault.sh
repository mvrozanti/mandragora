#!/usr/bin/env bash
set -euo pipefail

VAULT="${VAULT:-/home/m/Documents/mandragora-desktop-obsidian-vault}"
REMOTE="${REMOTE:-opc@mandragora-vps}"
REMOTE_DIR="${REMOTE_DIR:-/home/opc/demo/static}"

graph="$(mktemp --suffix=.json)"
trap 'rm -f "$graph"' EXIT

python3 "$(dirname "$(readlink -f "$0")")/build_graph.py" "$VAULT" "$graph"
python3 "$(dirname "$(readlink -f "$0")")/subject-dates.py" "$VAULT" "$graph"

rsync -a --delete \
  --exclude='.obsidian' \
  --exclude='.trash' \
  --exclude='.git' \
  "$VAULT/" "$REMOTE:$REMOTE_DIR/vault/"
rsync -a --chmod=F644 "$graph" "$REMOTE:$REMOTE_DIR/graph.json"

echo "published vault/ + graph.json → https://demo.mvr.ac/"
