#!/usr/bin/env bash

# Ensure submap is reset even if environment is sparse
if [ -z "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
    export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/$(id -u)/hypr/ | head -n 1)
fi

hyprctl dispatch submap reset >/dev/null
eww -c "$HOME/.config/eww" close powermenu
date +%s%N > "${XDG_RUNTIME_DIR:-/tmp}/powermenu-last-closed"
