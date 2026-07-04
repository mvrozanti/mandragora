#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/cve-scan"
LATEST="${STATE_DIR}/latest.json"
HOST="$(hostname)"
REMOTE="${VULN_REMOTE:-opc@100.84.78.83}"
REMOTE_DIR="${VULN_REMOTE_DIR:-/home/opc/vuln/static}"

if [[ ! -s "$LATEST" ]]; then
  echo "no scan report at $LATEST — run: systemctl --user start cve-scan.service" >&2
  exit 1
fi

GENERATED="$(readlink "$LATEST" 2>/dev/null | sed -E 's/\.json$//')"
: "${GENERATED:=unknown}"

SLIM="$(mktemp)"
trap 'rm -f "$SLIM"' EXIT

jq --arg gen "$GENERATED" --arg host "$HOST" '{
  generated: $gen,
  host: $host,
  entries: [ .[] | {
    pname: .pname,
    version: .version,
    max: ([ (.cvssv3_basescore // {}) | to_entries[].value ] | max // 0),
    cves: [ .affected_by[] as $c | {
      id: $c,
      score: ((.cvssv3_basescore // {})[$c] // 0),
      desc: ((.description // {})[$c] // "")
    } ]
  } ]
}' "$LATEST" > "$SLIM"

echo "→ publishing $(jq '.entries|length' "$SLIM") entries (generated $GENERATED) to $REMOTE:$REMOTE_DIR/report.json"
rsync -a "$SLIM" "$REMOTE:$REMOTE_DIR/report.json"
echo "→ done. https://vuln.mvr.ac"
