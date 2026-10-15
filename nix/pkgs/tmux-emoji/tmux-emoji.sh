#!/usr/bin/env bash
set -euo pipefail

DATA="${TMUX_EMOJI_DATA:?}"

list() {
  jq -r 'to_entries[] | [.key, (.value | join(" "))] | @tsv' "$DATA"
}

pick() {
  local pane="$1" line char
  if ! line="$(list | fzf --delimiter=$'\t' --nth=2 --with-nth=1,2 --layout=reverse --prompt='emoji> ')"; then
    return 0
  fi
  char="${line%%$'\t'*}"
  [ -n "$char" ] && tmux send-keys -l -t "$pane" -- "$char"
}

case "${1:-}" in
  --pick)
    pick "${2:?pane id required}"
    ;;
  *)
    client="${1:-}"
    pane="${2:?pane id required}"
    target=()
    [ -n "$client" ] && target=(-c "$client")
    tmux display-popup "${target[@]}" -E -w 60% -h 40% "$0 --pick $pane"
    ;;
esac
