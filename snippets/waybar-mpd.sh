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

  [[ "$state" == "playing" ]] && icon="" || icon=""
  class="$state"

  # Escape for JSON
  title=${title//\\/\\\\}; title=${title//\"/\\\"}
  artist=${artist//\\/\\\\}; artist=${artist//\"/\\\"}
  album=${album//\\/\\\\}; album=${album//\"/\\\"}

  printf '{"text": "  %s %s", "tooltip": "%s — %s (%s)", "class": "%s"}\n' \
    "$title" "$icon" "$artist" "$album" "$times" "$class"
}

output
while mpc idle player 2>/dev/null; do
  output
done
