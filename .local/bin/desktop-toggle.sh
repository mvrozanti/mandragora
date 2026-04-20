#!/usr/bin/env bash
current=$(hyprctl activeworkspace -j | jq -r '.id')
if [ "$current" = "1" ]; then
    hyprctl dispatch workspace previous
else
    hyprctl dispatch workspace 1
fi
