#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/../../deploy-guard.sh"
deploy_begin gpg "$HERE"
deploy_mkdir app data
deploy_rsync "$HERE/docker-compose.yml" :
deploy_rsync --delete --exclude='__pycache__/' --exclude='*.pyc' "$HERE/app/" :app/
deploy_up --build
deploy_end
