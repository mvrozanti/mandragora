#!/usr/bin/env bash
output() {
  if ! mpc status &>/dev/null; then
    echo '{"text": "", "class": "stopped"}'
    return
  fi

  state=$(mpc status 2>/dev/null | sed -n '2s/^\[\(.*\)\].*/\1/p')

  if [[ -z "$state" ]]; then
    echo '{"text": "", "class": "stopped"}'
    return
  fi

  title=$(mpc current -f "%title%")
  artist=$(mpc current -f "%artist%")
  album=$(mpc current -f "%album%")
  times=$(mpc status | sed -n '2s/.*[[:space:]]\+\([0-9:]*\/[0-9:]*\).*/\1/p')

  class="$state"

  for var in title artist album; do
    declare -n ref=$var
    ref=${ref//\\/\\\\}; ref=${ref//\"/\\\"}
    ref=${ref//&/&amp;}; ref=${ref//</&lt;}; ref=${ref//>/&gt;}
  done

  music=$'\uf001'
  printf '{"text": "%s  %s", "tooltip": "%s — %s (%s)", "class": "%s"}\n' \
    "$music" "$title" "$artist" "$album" "$times" "$class"
}

while true; do
  if mpc status &>/dev/null; then
    output
    mpc idle player &>/dev/null
  else
    echo '{"text": "", "class": "stopped"}'
    sleep 2
  fi
done
