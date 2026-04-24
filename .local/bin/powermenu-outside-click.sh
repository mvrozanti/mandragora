#!/usr/bin/env bash
set -eu

WIN=powermenu
GEOM_X=20
GEOM_Y=60
GEOM_W=380
GEOM_H=230

if ! eww -c "$HOME/.config/eww" active-windows 2>/dev/null | grep -qx "$WIN"; then
    hyprctl dispatch submap reset >/dev/null
    exit 0
fi

read -r cx cy < <(hyprctl cursorpos -j | jq -r '"\(.x) \(.y)"')
read -r mw mh < <(hyprctl monitors -j | jq -r '.[] | select(.focused) | "\(.width) \(.height)"')

left=$((mw - GEOM_X - GEOM_W))
right=$((mw - GEOM_X))
top=$((mh - GEOM_Y - GEOM_H))
bottom=$((mh - GEOM_Y))

if (( cx < left || cx > right || cy < top || cy > bottom )); then
    powermenu-close
fi
