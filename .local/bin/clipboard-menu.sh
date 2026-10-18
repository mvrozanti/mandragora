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
  list)
    cliphist -preview-width 300 list | awk -v n="${2:-200}" 'NR <= n'
    ;;
  copy)
    cliphist list | awk -F '\t' -v id="$2" '$1 == id { print; exit }' | cliphist decode | wl-copy
    ;;
  delete)
    cliphist list | awk -F '\t' -v id="$2" '$1 == id { print; exit }' | cliphist delete
    ;;
  thumb)
    dir="${XDG_CACHE_HOME:-$HOME/.cache}/clipboard-menu/thumbs"
    mkdir -p "$dir"
    out="$dir/$2.png"
    [ -s "$out" ] || printf '%s\t\n' "$2" | cliphist decode > "$out"
    printf '%s\n' "$out"
    ;;
  *)
    echo "usage: $(basename "$0") {pick|clear|list|copy ID|delete ID|thumb ID}" >&2
    exit 2
    ;;
esac
