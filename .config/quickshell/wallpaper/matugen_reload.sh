#!/usr/bin/env bash

# Persist last wallpaper path for restore-theme (WALL_FILE is exported by the picker)
if [[ -n "${WALL_FILE:-}" ]]; then
    mkdir -p ~/.cache/matugen
    echo "$WALL_FILE" > ~/.cache/matugen/last-wallpaper
fi

# Reload Kitty color scheme live
killall -USR1 .kitty-wrapped 2>/dev/null || true

# Reload waybar
pkill -SIGUSR2 waybar 2>/dev/null || true

# Reload mako notification daemon
makoctl reload 2>/dev/null || true

# Reload keyboard LED colors
keyledsd-reload 2>/dev/null || true

# GTK live-reload: rapidly toggle theme to flush GTK3/GTK4 CSS caches
if command -v gsettings &>/dev/null; then
    gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita'
    sleep 0.05
    gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
    gsettings set org.gnome.desktop.interface color-scheme 'default'
    sleep 0.05
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
fi
