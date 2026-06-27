#!/usr/bin/env bash
focused=$(hyprctl -j monitors all | jq -r '.[] | select(.focused) | .name')
current=$(hyprctl -j activeworkspace | jq -r '.id')
state="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/desktop-toggle-${focused}"

if [ -f "$state" ]; then
    prev=$(cat "$state")
    rm -f "$state"
    [ -n "$prev" ] && hyprctl dispatch workspace "$prev"
else
    echo "$current" > "$state"
    hyprctl dispatch workspace 1
fi
