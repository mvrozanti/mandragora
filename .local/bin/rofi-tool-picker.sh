#!/usr/bin/env bash
selected=$(printf 'zathura\nPostman\nBruno\nGpick\nHyprpicker' | rofi -dmenu -p "Tool")
case "$selected" in
    zathura)  zathura ;;
    Postman)  postman ;;
    Bruno)    bruno ;;
    Gpick)    gpick ;;
    Hyprpicker) hyprpicker -a ;;
esac
