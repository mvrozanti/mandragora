#!/usr/bin/env bash
set -euo pipefail

prompt=${1:?usage: vicinae-pick PROMPT < ICON<TAB>LABEL<TAB>COMMAND rows}

declare -A run
menu=
while IFS=$'\t' read -r icon label cmd; do
  [[ -n "$label" && -n "$cmd" ]] || continue
  command -v "${cmd%% *}" >/dev/null 2>&1 || continue
  run[$label]=$cmd
  menu+="$icon"$'\t'"$label"$'\n'
done

[[ -n "$menu" ]] || exit 0
choice=$(printf '%s' "$menu" | vicinae dmenu --icons -p "$prompt") || exit 0
[[ -n "${run[$choice]:-}" ]] || exit 0
exec sh -c "${run[$choice]}"
