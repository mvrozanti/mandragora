#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/../../deploy-guard.sh"
deploy_begin hub "$HERE"
deploy_rsync --delete --exclude='*.bak' --exclude='*.bak.*' "$HERE/static/" :static/
deploy_end
