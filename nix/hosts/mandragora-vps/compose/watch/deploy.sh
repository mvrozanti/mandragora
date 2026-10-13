#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/../../deploy-guard.sh"
deploy_begin watch "$HERE"
deploy_mkdir app data health
deploy_rsync "$HERE/docker-compose.yml" :
deploy_rsync --delete --exclude='__pycache__/' --exclude='*.pyc' --exclude='.pytest_cache/' "$HERE/app/" :app/
deploy_up --build
deploy_end
