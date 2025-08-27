#!/bin/bash
udevadm monitor --udev --subsystem-match=usb --property |
while read -r line; do
    if [[ "$line" == *"add"* ]]; then
        xset r rate 200 30
        setxkbmap us alt-intl
        xmodmap ~/.Xmodmap
    fi
done
