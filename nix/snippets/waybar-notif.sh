#!/usr/bin/env bash
state="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/mandragora-shell/notifications.json"
bell=$''
bell_slash=$''
phone_off=$'󰥐'

count=0
dnd=false
if [[ -r "$state" ]]; then
  count=$(jq -r '.count // 0' "$state" 2>/dev/null || echo 0)
  dnd=$(jq -r '.dnd // false' "$state" 2>/dev/null || echo false)
fi

phone=on
if command -v phone-forward >/dev/null; then
  phone=$(phone-forward state)
fi

case $count in
  0) summary="No notifications" ;;
  1) summary="1 notification" ;;
  *) summary="$count notifications" ;;
esac

if [[ "$dnd" == true ]]; then
  icon=$bell_slash
  class=dnd
  dnd_line="Do not disturb is on"
  right="right-click to turn it off"
else
  icon=$bell
  class=active
  dnd_line=""
  right="right-click for Do not disturb"
fi

if [[ "$phone" == off ]]; then
  icon="$icon $phone_off"
  phone_line="Phone notifications are off"
  middle="middle-click to turn them on"
else
  phone_line="Phone notifications are on"
  middle="middle-click to turn them off"
fi

head=$summary
[[ -n "$dnd_line" ]] && head="$head · $dnd_line"

jq -cn \
  --arg text "$icon" \
  --arg class "$class" \
  --arg phone "phone-$phone" \
  --arg tooltip "$head"$'\n'"$phone_line"$'\n'"click to open · $right · $middle" \
  '{text: $text, class: [$class, $phone], tooltip: $tooltip}'
