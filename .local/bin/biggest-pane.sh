#!/usr/bin/env bash
active_ws=$(hyprctl activeworkspace -j | jq -r '.id')
biggest=$(hyprctl clients -j | jq -r --argjson ws "$active_ws" '[.[] | select(.workspace.id == $ws and .mapped == true and .hidden == false)] | max_by(.size[0] * .size[1]) | .address')
[ -n "$biggest" ] && hyprctl dispatch focuswindow "address:$biggest"
