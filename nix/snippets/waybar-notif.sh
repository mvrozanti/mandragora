#!/usr/bin/env bash
state="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/mandragora-shell/notifications.json"
bell=$''
bell_slash=$''

count=0
dnd=false
if [[ -r "$state" ]]; then
  count=$(jq -r '.count // 0' "$state" 2>/dev/null || echo 0)
  dnd=$(jq -r '.dnd // false' "$state" 2>/dev/null || echo false)
fi

case $count in
  0) summary="No notifications" ;;
  1) summary="1 notification" ;;
  *) summary="$count notifications" ;;
esac

if [[ "$dnd" == true ]]; then
  printf '{"text": "%s", "class": "dnd", "tooltip": "%s · Do not disturb is on\\nclick to open · right-click to turn it off"}\n' "$bell_slash" "$summary"
else
  printf '{"text": "%s", "class": "active", "tooltip": "%s\\nclick to open · right-click for Do not disturb"}\n' "$bell" "$summary"
fi
