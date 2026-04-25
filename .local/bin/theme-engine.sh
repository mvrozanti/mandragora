WALLPAPER=$1
POS=$(hyprctl cursorpos | tr -d ' ')
swww img "$WALLPAPER" \
    --transition-type grow \
    --transition-pos "$POS" \
    --transition-duration 1
mkdir -p ~/.cache/matugen
echo "$WALLPAPER" > ~/.cache/matugen/last-wallpaper
matugen image "$WALLPAPER" --source-color-index 0 --quiet 2>/dev/null || true
wal-to-rgb
pkill -SIGUSR2 waybar || true
