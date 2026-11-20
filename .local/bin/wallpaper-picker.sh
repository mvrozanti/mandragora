#!/usr/bin/env bash
dir="${WALLPAPER_DIR:-$HOME/Pictures}"
selected=$(find "$dir" -maxdepth 3 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.webp" \) 2>/dev/null | sort | vicinae dmenu -p "Wallpaper")
[[ -n "$selected" ]] && setbg "$selected"
