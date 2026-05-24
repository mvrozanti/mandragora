#!/usr/bin/env bash
step=$1
read -r addr class <<<"$(hyprctl activewindow -j 2>/dev/null | jq -r '"\(.address // "") \(.class // "")"')"
[[ -z "$addr" ]] && exit 1
if [[ "$class" =~ ^(kitty|_zsh_|_lf_|_aerc_|ncmpcpp|ncmpcpp-float|irssi|tmux-float)$ ]]; then
    notify-send -t 2000 "opacity-adjust" "kitty: use ctrl+shift+j/k/l (bg only, fg stays opaque)"
    exit 0
fi
state_dir="/tmp/hypr-alpha"
mkdir -p "$state_dir"
state="$state_dir/$addr"
current=$(cat "$state" 2>/dev/null || echo "1.0")
new=$(awk "BEGIN { x=$current+($step); if(x>1.0)x=1.0; if(x<0.1)x=0.1; printf \"%.2f\", x }")
echo "$new" > "$state"
hyprctl dispatch setprop "address:$addr" opacity_override 1 >/dev/null
hyprctl dispatch setprop "address:$addr" opacity "$new" >/dev/null
hyprctl dispatch setprop "address:$addr" opacity_inactive_override 1 >/dev/null
hyprctl dispatch setprop "address:$addr" opacity_inactive "$new" >/dev/null
