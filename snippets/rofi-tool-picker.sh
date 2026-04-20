#!/usr/bin/env bash
selected=$(printf 'zathura\nPostman\nBruno' | rofi -dmenu -p "Tool")
case "$selected" in
    zathura)  zathura ;;
    Postman)  postman ;;
    Bruno)    bruno ;;
esac
