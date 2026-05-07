#!/usr/bin/env bash
set -u

src="${WALLPAPER_DIR:-$HOME/Pictures/wllpps}"
cache="$HOME/.cache/wallpaper_picker"
thumbs="$cache/thumbs"
mkdir -p "$thumbs" "$cache/colors_markers" "$cache/search_thumbs"

if [[ -d "$src" ]]; then
    shopt -s nullglob nocaseglob
    for f in "$src"/*.{jpg,jpeg,png,webp,gif}; do
        name="${f##*/}"
        [[ -e "$thumbs/$name" ]] && continue
        ln -s "$f" "$thumbs/$name" 2>/dev/null || true
    done
fi

cleanup() {
    hyprctl keyword unbind ',Escape' >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

hyprctl keyword bind ',Escape,exec,pkill -x quickshell' >/dev/null 2>&1 || true
quickshell
