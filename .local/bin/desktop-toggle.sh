#!/usr/bin/env bash
focused=$(hyprctl -j monitors all | jq -r '.[] | select(.focused) | .name')
current=$(hyprctl -j activeworkspace | jq -r '.id')
state="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/desktop-toggle-${focused}"

if [ "$current" = "1" ]; then
    prev=$(cat "$state" 2>/dev/null)
    rm -f "$state"
    [ -n "$prev" ] && hyprctl dispatch workspace "$prev"
else
    echo "$current" > "$state"
    hyprctl dispatch focusworkspaceoncurrentmonitor 1
fi
