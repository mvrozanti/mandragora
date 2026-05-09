#!/usr/bin/env bash
set -euo pipefail

action="${1:-pick}"

case "$action" in
  pick)
    history_json=$(makoctl history -j)
    count=$(printf '%s' "$history_json" | jq 'length')
    if [ "$count" -eq 0 ]; then
      notify-send -t 1500 "Notifications" "No notifications in history"
      exit 0
    fi
    display=$(printf '%s' "$history_json" | jq -r '
      def icon(u):
        if   u == 2 then ""
        elif u == 0 then ""
        else "" end;
      .[] |
        "\(icon(.urgency))  \(.app_name // "?"): \(((.summary // "") + (if (.body // "") != "" then " — " + .body else "" end)) | gsub("[\r\n\t]"; " ") | .[0:120])"
    ')
    idx=$(printf '%s\n' "$display" | rofi -dmenu -i -p "notifications" -format 'i') || exit 0
    [ -z "$idx" ] && exit 0
    id=$(printf '%s' "$history_json" | jq -r ".[$idx].id")
    [ -z "$id" ] || [ "$id" = "null" ] && exit 0
    if printf '%s' "$history_json" | jq -e ".[$idx].actions | has(\"default\")" >/dev/null 2>&1; then
      makoctl invoke -n "$id" default
    else
      makoctl restore >/dev/null 2>&1 || true
    fi
    ;;
  dnd)
    if makoctl mode | grep -qx do-not-disturb; then
      makoctl mode -r do-not-disturb
      notify-send -t 1500 "Notifications" "Do Not Disturb: off"
    else
      notify-send -t 1500 "Notifications" "Do Not Disturb: on"
      makoctl mode -a do-not-disturb
    fi
    ;;
  *)
    echo "usage: $(basename "$0") {pick|dnd}" >&2
    exit 2
    ;;
esac
