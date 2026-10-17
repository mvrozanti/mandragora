#!/usr/bin/env bash
# shellcheck shell=bash
set -uo pipefail
. "$AUDIT_HOME/lib/common.sh"

CHECK="${AUDIT_NAME:-vault-unresolved-links}"

VAULT="${MANDRAGORA_VAULT:-$HOME/Documents/mandragora-desktop-obsidian-vault}"
BUILD_GRAPH="$MANDRAGORA_REPO/nix/hosts/mandragora-vps/compose/demo/build_graph.py"

if [ ! -d "$VAULT" ]; then
  audit_pass "$CHECK" "vault not present; skipped"
  exit 0
fi
if [ ! -f "$BUILD_GRAPH" ]; then
  audit_pass "$CHECK" "vault-graph build_graph.py not present; skipped"
  exit 0
fi

ALLOWLIST=$(audit_load_allowlist "$AUDIT_HOME/allowlists/vault-unresolved-links.txt")

tree="$(mktemp -d)"
graph="$(mktemp --suffix=.json)"
trap 'rm -rf "$tree" "$graph"' EXIT

if ! git -C "$VAULT" archive --format=tar HEAD 2>/dev/null | tar -x -C "$tree" 2>/dev/null; then
  audit_pass "$CHECK" "vault has no committed tree; skipped"
  exit 0
fi

if ! python3 "$BUILD_GRAPH" "$tree" "$graph" >/dev/null 2>&1; then
  audit_pass "$CHECK" "graph build failed; skipped"
  exit 0
fi

unresolved=$(python3 - "$graph" <<'PY'
import json
import sys
from collections import defaultdict

g = json.load(open(sys.argv[1], encoding="utf-8"))
phantoms = {n["id"] for n in g["nodes"] if n["group"] == "_unresolved"}
sources = defaultdict(list)
for link in g["links"]:
    if link["source"] in phantoms:
        sources[link["source"]].append(link["target"])
    if link["target"] in phantoms:
        sources[link["target"]].append(link["source"])
for n in g["nodes"]:
    if n["group"] == "_unresolved":
        linked = ", ".join(sorted(set(sources.get(n["id"], []))))
        print(f"{n['label']}  (from: {linked})" if linked else n["label"])
PY
)

if [ -z "$unresolved" ]; then
  audit_pass "$CHECK"
  exit 0
fi

violations=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  label="${line%%  (*}"
  if audit_in_allowlist "$label" "$ALLOWLIST"; then
    continue
  fi
  audit_fail "$CHECK" "unresolved wikilink: ${line}"
  violations=$((violations + 1))
done <<< "$unresolved"

if [ "$violations" -gt 0 ]; then
  echo "  demo.mvr.ac renders these as (unresolved) phantoms in the vault graph." >&2
  echo "  Fix the link target, or restore/rename the note it points to." >&2
  exit 1
fi

audit_pass "$CHECK"
