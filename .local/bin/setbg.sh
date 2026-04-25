#!/usr/bin/env bash
set -u

dir="${WALLPAPER_DIR:-$HOME/Pictures/wllpps}"
fpath="${1:-}"
if [[ -z "$fpath" ]]; then
    fpath="$(find "$dir" -maxdepth 2 -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \
           -o -iname '*.gif' -o -iname '*.webp' \) 2>/dev/null | shuf | head -1)"
fi
if [[ -z "$fpath" || ! -e "$fpath" ]]; then
    exit 1
fi
fpath="$(realpath "$fpath")"

# hyprctl prints errors to stdout when it can't connect to the socket
pos="$(hyprctl cursorpos 2>/dev/null | grep -vE "Couldn't connect|Error" | tr -d ' ' || true)"
if [[ ! "$pos" =~ ^[0-9]+(\.[0-9]+)?,[0-9]+(\.[0-9]+)?$ ]]; then
    pos="960,540"
fi
awww img "$fpath" --transition-type grow --transition-pos "$pos" --transition-duration 1

wal -i "$fpath" -n -q 2>/dev/null || true

if tmux info &>/dev/null; then
    tmux source-file ~/.cache/wal/colors-tmux.conf
    tmux refresh-client -S 2>/dev/null || true
fi

if ! systemctl is-active --quiet openrgb; then
    # We now have NOPASSWD for this in security.nix
    sudo systemctl start openrgb
    sleep 1
fi

wal-to-rgb &>/dev/null &
systemctl --user start wal-to-rgb-daemon 2>/dev/null || true
hid-wrapper &>/dev/null &
keyledsd-reload &>/dev/null &
pkill -SIGUSR2 waybar 2>/dev/null || true
makoctl reload 2>/dev/null || true
hyprctl reload &>/dev/null || true
wait

