#!/usr/bin/env bash
set -euo pipefail

case "${1:-pick}" in
  pick)
    sel=$(cliphist list | rofi -dmenu -i -p "clipboard") || exit 0
    [ -z "$sel" ] && exit 0
    printf '%s\n' "$sel" | cliphist decode | wl-copy
    ;;
  clear)
    cliphist wipe
    ;;
  *)
    echo "usage: $(basename "$0") {pick|clear}" >&2
    exit 2
    ;;
esac
