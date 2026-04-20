#!/usr/bin/env bash
read -r x y w h _ < <(hyprctl activewindow -j | jq -r '.at[0], .at[1], .size[0], .size[1], ""' | tr '\n' ' ')
read -r sw sh < <(hyprctl monitors -j | jq -r '.[] | select(.focused) | "\(.width) \(.height)"')
nx=$(( (sw - w) / 2 ))
ny=$(( (sh - h) / 2 ))
hyprctl dispatch moveactive exact "$nx" "$ny"
