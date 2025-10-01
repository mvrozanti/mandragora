#!/bin/bash

if [ "$#" -ne 2 ]; then
    echo "Uso: $0 <width> <height>"
    exit 1
fi

width=$1
height=$2

win_id=$(xdotool getactivewindow)
eval $(xdotool getwindowgeometry --shell $win_id)

dx=$((width - WIDTH))
dy=$((height - HEIGHT))

bspc node -z right $dx 0
bspc node -z bottom 0 $dy

