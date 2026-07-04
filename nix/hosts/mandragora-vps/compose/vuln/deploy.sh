#!/usr/bin/env bash
# Deploy vuln.mvr.ac static dashboard to the VPS, then push this host's
# latest CVE report. Per-host report-*.json and hosts.json are gitignored
# (written by vuln-publish on each host), so the static rsync excludes them
# and never clobbers the live reports of other hosts.
set -euo pipefail

REPO_STATIC="$(cd "$(dirname "$0")/static" && pwd)"
REMOTE="${REMOTE:-opc@100.84.78.83}"
REMOTE_DIR="${REMOTE_DIR:-/home/opc/vuln/static}"

echo "→ rsyncing $REPO_STATIC/ to $REMOTE:$REMOTE_DIR/"
rsync -av --delete \
  --exclude='/report.json' \
  --exclude='/report-*.json' \
  --exclude='/hosts.json' \
  "$REPO_STATIC/" "$REMOTE:$REMOTE_DIR/"

if command -v vuln-publish >/dev/null 2>&1; then
  echo "→ pushing latest CVE report"
  vuln-publish || echo "  (no report yet — run cve-scan then vuln-publish)"
fi

echo "→ done. nginx serves new files immediately (no container restart)."
