#!/usr/bin/env bash
set -euo pipefail

case "${1:-pick}" in
  pick)
    while :; do
      set +e
      sel=$(cliphist -preview-width 240 list | rofi -dmenu \
          -theme "$HOME/.config/rofi/themes/menu.rasi" \
          -theme-str 'window { width: 38%; }
                      listview { lines: 14; }' \
          -matching fuzzy \
          -sort \
          -sorting-method fzf \
          -i \
          -no-fixed-num-lines \
          -kb-remove-char-forward '' \
          -kb-custom-1 'Delete')
      rc=$?
      set -e
      case $rc in
        0)
          [ -z "$sel" ] && exit 0
          printf '%s\n' "$sel" | cliphist decode | wl-copy
          exit 0
          ;;
        10)
          [ -z "$sel" ] && exit 0
          printf '%s\n' "$sel" | cliphist delete
          ;;
        *)
          exit 0
          ;;
      esac
    done
    ;;
  clear)
    cliphist wipe
    ;;
  *)
    echo "usage: $(basename "$0") {pick|clear}" >&2
    exit 2
    ;;
esac
