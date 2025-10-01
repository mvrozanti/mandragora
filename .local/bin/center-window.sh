#!/bin/bash

win_id=$(xdotool getactivewindow)
eval $(xdotool getwindowgeometry --shell $win_id)

screen_width=$(xdotool getdisplaygeometry | awk '{print $1}')
screen_height=$(xdotool getdisplaygeometry | awk '{print $2}')

pos_x=$(((screen_width - WIDTH) / 2))
pos_y=$(((screen_height - HEIGHT) / 2))

xdotool windowmove $win_id $pos_x $pos_y
