#!/usr/bin/env bash
# Mandragora Dynamic Theming Engine (Pywal Pipeline)
# This script extracts colors from a wallpaper and injects them into the environment.

WALLPAPER=$1

if [ -z "$WALLPAPER" ]; then
    echo "Usage: $0 /path/to/wallpaper"
    exit 1
fi

echo "Extracting colors from $WALLPAPER..."

# Run pywal to generate colors (requires python3Packages.pywal installed)
wal -i "$WALLPAPER" -n

# Example of updating tools (uncomment when configured):
# hyprctl hyprpaper wallpaper "DP-1,$WALLPAPER"
# killall -USR1 kitty
# killall -SIGUSR2 waybar

echo "Theme updated successfully."
