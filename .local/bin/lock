#!/bin/bash
IFS=$'\n' read -d '' -r -a colors < ~/.cache/wal/colors
i3-msg workspace 9 && sleep 0.1
transp=70
i3lock -k --blur=10 -b \
    --pass-media-keys --pass-screen-keys --pass-power-keys \
    --insidevercolor=${colors[0]:1}$transp \
    --insidewrongcolor=${colors[1]:1}$transp \
    --ringvercolor=${colors[2]:1}$transp \
    --ringwrongcolor=${colors[3]:1}$transp \
    --insidecolor=${colors[4]:1}$transp \
    --ringcolor=${colors[5]:1}$transp \
    --keyhlcolor=${colors[6]:1}$transp \
    --bshlcolor=${colors[7]:1}$transp \
    --separatorcolor=${colors[8]:1}$transp \
    --verifcolor=${colors[9]:1}$transp \
    --wrongcolor=ffffffff \
    --layoutcolor=${colors[11]:1}$transp \
    --timecolor=${colors[12]:1}66 \
    --linecolor=${colors[13]:1}66 \
    --datecolor=${colors[14]:1}66 \
    --radius 250 \
    --wrongtext="no" \
    --veriftext="" \
    --noinputtext="text"
