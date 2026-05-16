#!/usr/bin/env bash
set -euo pipefail

case "${1:-pick}" in
  pick)
    sel=$(cliphist -preview-width 240 list | rofi -dmenu \
        -theme "$HOME/.config/rofi/themes/menu.rasi" \
        -theme-str 'window { width: 38%; }
                    listview { lines: 14; }' \
        -matching fuzzy \
        -sort \
        -sorting-method fzf \
        -i \
        -no-fixed-num-lines) || exit 0
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
