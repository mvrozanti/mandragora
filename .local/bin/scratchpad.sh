#!/usr/bin/env bash
addr=$(hyprctl activewindow -j | jq -r '.address')
[ -z "$addr" ] || [ "$addr" = "null" ] || [ "$addr" = "0x0" ] && exit 0
hyprctl dispatch movetoworkspacesilent "special:scratchpad,address:$addr"
echo "$addr" >> /tmp/scratchpad-stack
