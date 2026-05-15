#!/usr/bin/env bash
set -euo pipefail

case "${1:-pick}" in
  pick)
    sel=$(cliphist -preview-width 240 list | rofi -dmenu \
        -theme "$HOME/.config/rofi/themes/menu.rasi" \
        -theme-str 'window { width: 38%; }
                    listview { lines: 8; }
                    element { padding: 10px 12px; }
                    element-text { vertical-align: 0.5; }' \
        -eh 2 \
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
