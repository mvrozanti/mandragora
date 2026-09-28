#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/cve-scan"
LATEST="${STATE_DIR}/latest.json"
HOST="$(hostname)"
REMOTE="${VULN_REMOTE:-opc@100.84.78.83}"
REMOTE_DIR="${VULN_REMOTE_DIR:-/home/opc/vuln/static}"
SCAN_ERROR="${VULN_SCAN_ERROR:-}"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=15)

if [[ ! -s "$LATEST" ]]; then
  echo "no scan report at $LATEST — run: systemctl --user start cve-scan.service" >&2
  exit 1
fi

GENERATED="$(date -u -r "$LATEST" +%Y-%m-%dT%H:%M:%SZ)"

SLIM="$(mktemp)"
trap 'rm -f "$SLIM"' EXIT

jq --arg gen "$GENERATED" --arg host "$HOST" --arg err "$SCAN_ERROR" '{
  schema: 2,
  scanner: "vulnix",
  generated: $gen,
  host: $host,
  entries: [ .[] | {
    pname: .pname,
    version: .version,
    ecosystem: "nixpkgs",
    max: ([ (.cvssv3_basescore // {}) | to_entries[].value ] | max // 0),
    cves: [ .affected_by[] as $c | {
      id: $c,
      score: ((.cvssv3_basescore // {})[$c] // 0),
      desc: ((.description // {})[$c] // "")
    } ]
  } ]
} + (if $err == "" then {} else {error: $err} end)' "$LATEST" > "$SLIM"

REPORT="report-${HOST}.json"
echo "→ publishing $(jq '.entries|length' "$SLIM") entries as ${HOST} (generated ${GENERATED}) to ${REMOTE}:${REMOTE_DIR}/${REPORT}"
rsync -a -e "ssh ${SSH_OPTS[*]}" "$SLIM" "${REMOTE}:${REMOTE_DIR}/${REPORT}"

EXPOSURE="${VULN_EXPOSURE:-/run/vuln-exposure/exposure.json}"
if [[ -s "$EXPOSURE" ]]; then
  echo "→ publishing $(jq '.listeners|length' "$EXPOSURE") exposed listener(s) as exposure-${HOST}.json"
  rsync -a -e "ssh ${SSH_OPTS[*]}" "$EXPOSURE" "${REMOTE}:${REMOTE_DIR}/exposure-${HOST}.json"
fi

ssh "${SSH_OPTS[@]}" "$REMOTE" bash -s "$REMOTE_DIR" <<'EOSSH'
set -euo pipefail
cd "$1"
printf '[%s]\n' "$(ls report-*.json 2>/dev/null | sed -E 's/^report-(.*)\.json$/"\1"/' | paste -sd, -)" > hosts.json
EOSSH

echo "→ done. https://vuln.mvr.ac"
