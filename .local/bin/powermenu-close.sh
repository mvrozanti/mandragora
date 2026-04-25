#!/usr/bin/env bash
hyprctl dispatch submap reset >/dev/null
eww -c "$HOME/.config/eww" close powermenu
date +%s%N > "${XDG_RUNTIME_DIR:-/tmp}/powermenu-last-closed"
