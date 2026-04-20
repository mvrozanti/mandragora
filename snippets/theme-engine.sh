WALLPAPER=$1
POS=$(hyprctl cursorpos | tr -d ' ')
swww img "$WALLPAPER" \
    --transition-type grow \
    --transition-pos "$POS" \
    --transition-duration 1
wal -i "$WALLPAPER" -n
wal-to-rgb
pkill -SIGUSR2 waybar || true
