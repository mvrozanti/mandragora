#!/usr/bin/env bash

emit() {
  local vol muted pct icon class
  vol=$(pamixer --get-volume 2>/dev/null || echo 0)
  muted=$(pamixer --get-mute 2>/dev/null || echo false)

  pct=$(( (vol + 2) / 5 * 5 ))
  (( pct > 100 )) && pct=100

  if [[ "$muted" == "true" ]]; then
    icon="󰝟"
    class="muted"
  else
    if (( vol == 0 )); then icon="󰝟"
    elif (( vol <= 30 )); then icon="󰕿"
    elif (( vol <= 70 )); then icon="󰖀"
    else icon="󰕾"
    fi
    class="v${pct}"
  fi

  printf '{"text": "%s %d%%", "class": "%s", "tooltip": "Volume: %d%%", "percentage": %d}\n' \
    "$icon" "$vol" "$class" "$vol" "$vol"
}

emit

pactl subscribe 2>/dev/null | grep --line-buffered -E "^Event '(change|new|remove)' on (sink|server) " | while IFS= read -r _; do
  while IFS= read -r -t 0.08 _; do :; done
  emit
done
