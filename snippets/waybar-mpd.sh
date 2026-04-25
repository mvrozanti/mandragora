#!/usr/bin/env bash
output() {
  status=$(mpc status 2>/dev/null)
  if [[ -z "$status" ]]; then
    echo '{"text": "", "class": "stopped"}'
    return
  fi

  state=$(echo "$status" | sed -n '2s/^\[\(.*\)\].*/\1/p')

  if [[ -z "$state" ]]; then
    echo '{"text": "", "class": "stopped"}'
    return
  fi

  title=$(mpc current -f "%title%")
  artist=$(mpc current -f "%artist%")
  album=$(mpc current -f "%album%")
  times=$(echo "$status" | sed -n '2s/.*[[:space:]]\+\([0-9:]*\/[0-9:]*\).*/\1/p')
  vol=$(echo "$status" | sed -n 's/^volume:[[:space:]]*\([0-9]*\)%.*/\1/p')

  [[ "$state" == "playing" ]] && icon=$'\uf04b' || icon=$'\uf04c'
  class="$state"

  for var in title artist album; do
    declare -n ref=$var
    ref=${ref//\\/\\\\}; ref=${ref//\"/\\\"}
    ref=${ref//&/&amp;}; ref=${ref//</&lt;}; ref=${ref//>/&gt;}
  done

  music=$'\uf001'
  printf '{"text": "%s  %s %s  %s%%", "tooltip": "%s — %s (%s)", "class": "%s"}\n' \
    "$music" "$title" "$icon" "${vol:-0}" "$artist" "$album" "$times" "$class"
}

while true; do
  output
  mpc idle player mixer &>/dev/null || sleep 2
done
