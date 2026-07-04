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

REPORT="report-${HOST}.json"
echo "→ publishing $(jq '.entries|length' "$SLIM") entries as ${HOST} (generated ${GENERATED}) to ${REMOTE}:${REMOTE_DIR}/${REPORT}"
rsync -a "$SLIM" "${REMOTE}:${REMOTE_DIR}/${REPORT}"

# Regenerate the host manifest from the directory listing on the VPS so the
# dashboard can enumerate every host that has ever published. Each publish
# self-heals the manifest, so a race between hosts just recomputes the union.
# The remote body is a quoted heredoc (no client-side expansion); REMOTE_DIR
# is passed as the positional arg.
ssh "$REMOTE" bash -s "$REMOTE_DIR" <<'EOSSH'
set -euo pipefail
cd "$1"
printf '[%s]\n' "$(ls report-*.json 2>/dev/null | sed -E 's/^report-(.*)\.json$/"\1"/' | paste -sd, -)" > hosts.json
EOSSH

echo "→ done. https://vuln.mvr.ac"
