#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/../../deploy-guard.sh"
deploy_begin mvr-api "$HERE"
deploy_mkdir
deploy_rsync --delete --exclude=.env --exclude=.no-deploy --exclude=/deploy.sh --exclude=/README.md --exclude=__pycache__/ "$HERE/" :
deploy_up --build
deploy_end
