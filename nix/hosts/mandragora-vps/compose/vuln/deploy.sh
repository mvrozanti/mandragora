#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/../../deploy-guard.sh"
deploy_begin vuln "$HERE"
deploy_rsync --delete --exclude=/report.json --exclude='/report-*.json' --exclude='/exposure-*.json' --exclude=/hosts.json "$HERE/static/" :static/
deploy_end
if [ "${DEPLOY_MODE:-deploy}" = deploy ] && command -v vuln-publish >/dev/null 2>&1; then
  vuln-publish || echo "  (no report yet: run cve-scan, then vuln-publish)"
fi
