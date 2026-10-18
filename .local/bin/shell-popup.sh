#!/usr/bin/env bash
set -euo pipefail

name=${1:?usage: shell-popup NAME [-- FALLBACK...]}
shift
[[ "${1:-}" == "--" ]] && shift

if systemctl --user is-active --quiet mandragora-shell.service \
  && [[ "$(mandragora-shell toggle "$name" 2>/dev/null)" == ok ]]; then
  exit 0
fi

(( $# )) && exec "$@"
exit 1
