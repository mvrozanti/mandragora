#!/usr/bin/env bash
ADDR=$(hyprctl clients -j | jq -r '.[] | select(.class == "obsidian") | .address' | head -1)
if [ -n "$ADDR" ]; then
    WS=$(hyprctl clients -j | jq -r --arg a "$ADDR" '.[] | select(.address == $a) | .workspace.id')
    hyprctl dispatch workspace "$WS"
    hyprctl dispatch focuswindow "address:$ADDR"
    hyprctl dispatch bringactivetotop
else
    hyprctl dispatch exec '[workspace 41] obsidian'
fi
