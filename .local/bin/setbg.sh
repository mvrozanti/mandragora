#!/usr/bin/env bash
dir="${WALLPAPER_DIR:-$HOME/Pictures}"
fpath="${1:-$(find "$dir" -maxdepth 2 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.webp' \) 2>/dev/null | shuf | head -1)}"
[[ -z "$fpath" ]] && { echo "No wallpaper found in $dir"; exit 1; }
fpath="$(realpath "$fpath")"
awww img "$fpath" --transition-type grow --transition-pos center --transition-duration 1
