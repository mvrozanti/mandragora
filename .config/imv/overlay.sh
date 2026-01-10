#!/bin/bash
while true; do
    if [ -n "$IMV_PATH" ]; then
        ~/.config/imv/imv-info.sh "$IMV_PATH" $(identify -format '%w %h' "$IMV_PATH" 2>/dev/null)
    fi
    sleep 1
done