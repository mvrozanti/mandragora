#!/usr/bin/env bash
corner="$1"
w=620
h=400
pad=10

monitor=$(hyprctl monitors -j | jq '.[0]')
sw=$(echo "$monitor" | jq '.width')
sh=$(echo "$monitor" | jq '.height')

case $corner in
    top-left)     x=$pad;             y=$pad ;;
    top-right)    x=$((sw - w - pad)); y=$pad ;;
    bottom-left)  x=$pad;             y=$((sh - h - pad)) ;;
    bottom-right) x=$((sw - w - pad)); y=$((sh - h - pad)) ;;
    *) exit 1 ;;
esac

hyprctl dispatch togglefloating
hyprctl dispatch resizeactive exact $w $h
hyprctl dispatch moveactive exact $x $y
