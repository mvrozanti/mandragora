#!/usr/bin/env bash
step=$1
addr=$(hyprctl activewindow -j 2>/dev/null | jq -r '.address // empty')
[[ -z "$addr" ]] && exit 1
state_dir="/tmp/hypr-alpha"
mkdir -p "$state_dir"
state="$state_dir/$addr"
current=$(cat "$state" 2>/dev/null || echo "1.0")
new=$(awk "BEGIN { x=$current+($step); if(x>1.0)x=1.0; if(x<0.1)x=0.1; printf \"%.2f\", x }")
echo "$new" > "$state"
hyprctl keyword setprop "address:$addr" alphaoverride "$new" >/dev/null
hyprctl keyword setprop "address:$addr" alphainactiveoverride "$new" >/dev/null
