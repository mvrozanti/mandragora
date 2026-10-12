#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/../../deploy-guard.sh"
deploy_begin food "$HERE"
deploy_mkdir data
deploy_rsync --delete --exclude=/data/ --exclude=.env --exclude=.no-deploy --exclude=/deploy.sh --exclude=/README.md --exclude=__pycache__/ "$HERE/" :
deploy_up --build
deploy_end
