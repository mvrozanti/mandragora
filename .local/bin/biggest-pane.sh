#!/usr/bin/env bash
n=${1:-1}
active_ws=$(hyprctl activeworkspace -j | jq -r '.id')
biggest=$(hyprctl clients -j | jq -r --argjson ws "$active_ws" --argjson n "$n" '
  [.[] | select(.workspace.id == $ws and .mapped == true and .hidden == false)]
  | sort_by(.size[0] * .size[1])
  | reverse
  | .[$n-1]
  | .address
')
[ -n "$biggest" ] && hyprctl dispatch focuswindow "address:$biggest"
