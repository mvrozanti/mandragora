#!/usr/bin/env bash
hyprctl keyword unbind ",mouse:272" >/dev/null 2>&1 || true
hyprctl keyword unbind ",mouse:273" >/dev/null 2>&1 || true
hyprctl keyword unbind ",mouse:274" >/dev/null 2>&1 || true
hyprctl dispatch submap reset >/dev/null
eww -c "$HOME/.config/eww" close powermenu
date +%s%N > "${XDG_RUNTIME_DIR:-/tmp}/powermenu-last-closed"
