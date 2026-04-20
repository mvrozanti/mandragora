#!/usr/bin/env bash
w=$(hyprctl activewindow -j)
x=$(echo "$w" | jq -r '.at[0]')
y=$(echo "$w" | jq -r '.at[1]')
width=$(echo "$w" | jq -r '.size[0]')
height=$(echo "$w" | jq -r '.size[1]')
grim -g "${x},${y} ${width}x${height}" - | wl-copy
