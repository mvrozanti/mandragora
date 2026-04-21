#!/usr/bin/env bash
# One-button ricing cascade: wallpaper → pywal → every themable surface.
set -u

dir="${WALLPAPER_DIR:-$HOME/Pictures/wllpps}"
fpath="${1:-}"
if [[ -z "$fpath" ]]; then
    fpath="$(find "$dir" -maxdepth 2 -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \
           -o -iname '*.gif' -o -iname '*.webp' \) 2>/dev/null | shuf | head -1)"
fi
if [[ -z "$fpath" || ! -e "$fpath" ]]; then
    notify-send -u critical "setbg" "No wallpaper found in $dir" 2>/dev/null || true
    echo "setbg: no wallpaper found in $dir" >&2
    exit 1
fi
fpath="$(realpath "$fpath")"

pos="$(hyprctl cursorpos 2>/dev/null | tr -d ' ' || true)"
pos="${pos:-960,540}"
awww img "$fpath" \
    --transition-type grow \
    --transition-pos "$pos" \
    --transition-duration 1

wal -i "$fpath" -n -q

wal-to-rgb &
hid-wrapper &
keyledsd-reload &
pkill -SIGUSR2 waybar 2>/dev/null || true
makoctl reload 2>/dev/null || pkill -SIGUSR1 dunst 2>/dev/null || true
wait

notify-send -t 2500 "Theme" "$(basename "$fpath")" 2>/dev/null || true
