#!/usr/bin/env bash
vol=$(pamixer --get-volume 2>/dev/null || echo 0)
muted=$(pamixer --get-mute 2>/dev/null || echo false)

filled=$(( vol * 15 / 100 ))
empty=$(( 15 - filled ))

on="#6eaafb"
off="#3b4048"

if [[ "$muted" == "true" ]]; then
  icon="󰝟"
  class="muted"
  on="#4b5263"
  off="#4b5263"
else
  if (( vol == 0 )); then icon="󰝟"
  elif (( vol <= 30 )); then icon="󰕿"
  elif (( vol <= 70 )); then icon="󰖀"
  else icon="󰕾"
  fi
  class="vol-$((vol / 20))"
fi

filled_str=$(printf '━%.0s' $(seq 1 $filled 2>/dev/null))
empty_str=$(printf '━%.0s' $(seq 1 $empty 2>/dev/null))

bar="<span color='${on}'>${filled_str}</span><span color='${off}'>${empty_str}</span>"

printf '{"text": "%s %s", "class": "%s", "tooltip": "Volume: %d%%", "percentage": %d}\n' \
  "$icon" "$bar" "$class" "$vol" "$vol"
