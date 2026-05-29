#!/usr/bin/env bash
if pkill -x wshowkeys; then
    exit 0
fi
exec /run/wrappers/bin/wshowkeys \
    -F 'Iosevka Nerd Font Mono 22' \
    -t 2 \
    -a bottom \
    -m 80 \
    -b '#000000c0' \
    -f '#ffffff' \
    -s '#cc6666'
