#!/usr/bin/env bash
set -eu

EWW=(eww -c "$HOME/.config/eww")
WIN=powermenu
SELF="$HOME/.local/bin/powermenu"
GEOM_X=20
GEOM_Y=60
GEOM_W=280
GEOM_H=320

is_open() {
    "${EWW[@]}" active-windows 2>/dev/null | grep -q "^$WIN:"
}

install_outside_binds() {
    hyprctl keyword bind "n,mouse:272,exec,$SELF outside-click" >/dev/null
    hyprctl keyword bind "n,mouse:273,exec,$SELF outside-click" >/dev/null
    hyprctl keyword bind "n,mouse:274,exec,$SELF outside-click" >/dev/null
}

remove_outside_binds() {
    hyprctl keyword unbind ",mouse:272" >/dev/null 2>&1 || true
    hyprctl keyword unbind ",mouse:273" >/dev/null 2>&1 || true
    hyprctl keyword unbind ",mouse:274" >/dev/null 2>&1 || true
}

case "${1:-}" in
    toggle)
        if is_open; then
            "${EWW[@]}" close "$WIN"
            remove_outside_binds
        else
            "${EWW[@]}" open "$WIN"
            install_outside_binds
        fi
        ;;
    close)
        "${EWW[@]}" close "$WIN" 2>/dev/null || true
        remove_outside_binds
        ;;
    outside-click)
        if ! is_open; then
            remove_outside_binds
            exit 0
        fi
        read -r cx cy < <(hyprctl cursorpos -j | jq -r '"\(.x) \(.y)"')
        read -r mw mh < <(hyprctl monitors -j | jq -r '.[] | select(.focused) | "\(.width) \(.height)"')
        left=$((mw - GEOM_X - GEOM_W))
        right=$((mw - GEOM_X))
        top=$((mh - GEOM_Y - GEOM_H))
        bottom=$((mh - GEOM_Y))
        if (( cx < left || cx > right || cy < top || cy > bottom )); then
            "${EWW[@]}" close "$WIN"
            remove_outside_binds
        fi
        ;;
    *)
        echo "usage: $0 {toggle|close|outside-click}" >&2
        exit 1
        ;;
esac
