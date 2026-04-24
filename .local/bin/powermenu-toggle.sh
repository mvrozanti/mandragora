#!/usr/bin/env bash
STAMP="${XDG_RUNTIME_DIR:-/tmp}/powermenu-last-closed"

if eww -c "$HOME/.config/eww" active-windows | grep -qx "powermenu"; then
    powermenu-close
    exit 0
fi

if [ -f "$STAMP" ]; then
    now=$(date +%s%N)
    last=$(cat "$STAMP")
    if (( (now - last) < 300000000 )); then
        exit 0
    fi
fi

eww -c "$HOME/.config/eww" open powermenu
hyprctl dispatch submap powermenu >/dev/null
hyprctl keyword bind "n,,mouse:272,exec,powermenu-outside-click" >/dev/null
hyprctl keyword bind "n,,mouse:273,exec,powermenu-outside-click" >/dev/null
hyprctl keyword bind "n,,mouse:274,exec,powermenu-outside-click" >/dev/null
