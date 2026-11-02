#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/../../deploy-guard.sh"
deploy_begin hub "$HERE"
deploy_mkdir host-stats served-hosts static
deploy_rsync "$HERE/docker-compose.yml" :
deploy_rsync --delete --exclude='__pycache__/' --exclude='*.pyc' "$HERE/host-stats/" :host-stats/
deploy_rsync --delete "$HERE/served-hosts/" :served-hosts/
deploy_rsync --delete --exclude='*.bak' --exclude='*.bak.*' "$HERE/static/" :static/
deploy_up
deploy_end
