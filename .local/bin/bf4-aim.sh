#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  on)  hyprctl keyword input:sensitivity -0.5 ;;
  off) hyprctl keyword input:sensitivity 0 ;;
  *)   echo "usage: bf4-aim {on|off}" >&2; exit 1 ;;
esac
