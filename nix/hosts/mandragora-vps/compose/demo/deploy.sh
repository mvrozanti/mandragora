#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/../../deploy-guard.sh"
deploy_begin demo "$HERE"
deploy_rsync --delete --exclude=/vault/ --exclude=/vault-graph/ --exclude=/graph.json "$HERE/static/" :static/
deploy_end
