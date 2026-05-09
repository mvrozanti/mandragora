#!/usr/bin/env bash
set -euo pipefail

EWW=(eww -c "$HOME/.config/eww")
WIN=capture-menu
SELF="$HOME/.local/bin/capture"
GEOM_X=12
GEOM_Y=56
GEOM_W=480
GEOM_H=380
STAMP="${XDG_RUNTIME_DIR:-/tmp}/capture-last-closed"

ts() { date +%Y%m%d-%H%M%S; }

layer_present() {
  hyprctl layers -j 2>/dev/null \
    | jq -r '.[].levels | to_entries[] | .value[] | .namespace' \
    | grep -qx "eww-capture"
}

is_open() {
  "${EWW[@]}" active-windows 2>/dev/null | grep -q "^$WIN:" && return 0
  layer_present
}

force_recover() {
  pkill -KILL -f "^eww open capture-menu" 2>/dev/null || true
  pkill -KILL -f "^eww .* open .*capture-menu" 2>/dev/null || true
  pkill -KILL -x "eww" 2>/dev/null || true
  pkill -KILL -f "eww daemon" 2>/dev/null || true
  remove_outside_binds
  hyprctl dispatch submap reset >/dev/null 2>&1 || true
  rm -f /run/user/$(id -u)/eww-server_* 2>/dev/null
  setsid eww -c "$HOME/.config/eww" daemon >/dev/null 2>&1 &
  disown 2>/dev/null || true
}

has_mic() { [[ "$(screencap has-mic)" == yes ]]; }
is_recording() { [[ "$(screencap is-recording)" == yes ]]; }

is_disabled() {
  local action="$1"
  case "$action" in
    vid-mic-*) ! has_mic && return 0 ;;
  esac
  if is_recording && [[ "$action" == vid-* ]]; then return 0; fi
  return 1
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

ensure_daemon() {
  if pgrep -x eww >/dev/null 2>&1; then
    local sock; sock=$(ls /run/user/$(id -u)/eww-server_* 2>/dev/null | head -1)
    [[ -S "$sock" ]] && return 0
  fi
  setsid eww -c "$HOME/.config/eww" daemon >/dev/null 2>&1 &
  for _ in $(seq 1 60); do
    local sock; sock=$(ls /run/user/$(id -u)/eww-server_* 2>/dev/null | head -1)
    [[ -S "$sock" ]] && return 0
    sleep 0.025
  done
}

open_menu() {
  ensure_daemon
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

wait_layer_gone() {
  for _ in $(seq 1 40); do
    layer_present || return 0
    sleep 0.025
  done
}

run_action() {
  close_menu
  wait_layer_gone
  case "$1" in
    shot-region|shot-full|shot-window|vid-none-region|vid-none-full|vid-none-window|vid-mic-region|vid-mic-full|vid-mic-window|vid-sys-region|vid-sys-full|vid-sys-window)
      screencap "$1"
      ;;
    *) echo "unknown action: $1" >&2; return 1 ;;
  esac
}

case "${1:-toggle}" in
  toggle)
    if is_recording; then screencap stop; exit 0; fi
    if "${EWW[@]}" active-windows 2>/dev/null | grep -q "^$WIN:"; then
      close_menu; exit 0
    fi
    if layer_present; then
      force_recover; exit 0
    fi
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
  shot-region|shot-full|shot-window|vid-none-region|vid-none-full|vid-none-window|vid-mic-region|vid-mic-full|vid-mic-window|vid-sys-region|vid-sys-full|vid-sys-window)
    run_action "$1"
    ;;
  stop) close_menu; screencap stop ;;
  panic) force_recover; "${EWW[@]}" close "$WIN" 2>/dev/null || true ;;
  *) echo "usage: $0 {toggle|close|outside-click|shot-{region,full,window}|vid-{none,mic,sys}-{region,full,window}|stop|panic}" >&2; exit 2 ;;
esac
