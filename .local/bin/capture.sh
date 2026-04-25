#!/usr/bin/env bash
set -euo pipefail

EWW=(eww -c "$HOME/.config/eww")
WIN=capture-menu
SELF="$HOME/.local/bin/capture"
GEOM_X=12
GEOM_Y=56
GEOM_W=460
GEOM_H=280
STAMP="${XDG_RUNTIME_DIR:-/tmp}/capture-last-closed"

shots_dir="$HOME/Pictures/Screenshots"
mkdir -p "$shots_dir"

ts() { date +%Y%m%d-%H%M%S; }

is_open() {
  "${EWW[@]}" active-windows 2>/dev/null | grep -q "^$WIN:"
}

install_outside_binds() {
  hyprctl keyword bind "n,mouse:272,exec,$SELF outside-click" >/dev/null
  hyprctl keyword bind "n,mouse:273,exec,$SELF outside-click" >/dev/null
  hyprctl keyword bind "n,mouse:274,exec,$SELF outside-click" >/dev/null
}

remove_outside_binds() {
  hyprctl keyword unbind ",mouse:272" >/dev/null 2>&1 || true
  hyprctl keyword unbind ",mouse:273" >/dev/null 2>&1 || true
  hyprctl keyword unbind ",mouse:274" >/dev/null 2>&1 || true
}

open_menu() {
  "${EWW[@]}" open "$WIN"
  hyprctl dispatch submap capture >/dev/null
  install_outside_binds
}

close_menu() {
  remove_outside_binds
  hyprctl dispatch submap reset >/dev/null 2>&1 || true
  "${EWW[@]}" close "$WIN" 2>/dev/null || true
  date +%s%N > "$STAMP"
}

is_recording() {
  local pf="${XDG_RUNTIME_DIR:-/tmp}/screencap.pid"
  [[ -f "$pf" ]] && kill -0 "$(cat "$pf")" 2>/dev/null
}

notify() {
  command -v notify-send >/dev/null && notify-send -a capture "$@" || true
}

shot_region() {
  XDG_CURRENT_DESKTOP=sway flameshot gui --path "$shots_dir" --clipboard
}

shot_full() {
  local file="$shots_dir/full-$(ts).png"
  grim "$file"
  wl-copy < "$file"
  notify -i "$file" "Screenshot" "$(basename "$file")"
}

shot_window() {
  local w x y width height file
  w=$(hyprctl activewindow -j)
  x=$(echo "$w" | jq -r '.at[0]')
  y=$(echo "$w" | jq -r '.at[1]')
  width=$(echo "$w" | jq -r '.size[0]')
  height=$(echo "$w" | jq -r '.size[1]')
  file="$shots_dir/window-$(ts).png"
  grim -g "${x},${y} ${width}x${height}" "$file"
  wl-copy < "$file"
  notify -i "$file" "Screenshot" "$(basename "$file")"
}

case "${1:-toggle}" in
  toggle)
    if is_recording; then screencap stop; exit 0; fi
    if is_open; then close_menu; exit 0; fi
    if [[ -f "$STAMP" ]]; then
      now=$(date +%s%N); last=$(cat "$STAMP")
      (( (now - last) < 300000000 )) && exit 0
    fi
    open_menu
    ;;
  close)        close_menu ;;
  outside-click)
    is_open || { remove_outside_binds; exit 0; }
    read -r cx cy < <(hyprctl cursorpos -j | jq -r '"\(.x) \(.y)"')
    read -r mw mh < <(hyprctl monitors -j | jq -r '.[] | select(.focused) | "\(.width) \(.height)"')
    left=$((mw - GEOM_X - GEOM_W))
    right=$((mw - GEOM_X))
    top=$((mh - GEOM_Y - GEOM_H))
    bottom=$((mh - GEOM_Y))
    if (( cx < left || cx > right || cy < top || cy > bottom )); then
      close_menu
    fi
    ;;
  shot-region)  close_menu; shot_region ;;
  shot-full)    close_menu; shot_full ;;
  shot-window)  close_menu; shot_window ;;
  rec-region)   close_menu; CAPTURE_NO_AUDIO=1 screencap region ;;
  rec-region-a) close_menu; screencap region ;;
  rec-full)     close_menu; CAPTURE_NO_AUDIO=1 screencap fullscreen ;;
  rec-full-a)   close_menu; screencap fullscreen ;;
  stop)         close_menu; screencap stop ;;
  *) echo "usage: $0 {toggle|close|outside-click|shot-region|shot-full|shot-window|rec-region|rec-region-a|rec-full|rec-full-a|stop}" >&2; exit 2 ;;
esac
