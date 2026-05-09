#!/usr/bin/env bash
set -euo pipefail

EWW=(eww -c "$HOME/.config/eww")
WIN=powermenu
SELF="$HOME/.local/bin/powermenu"
GEOM_X=12
GEOM_Y=56
GEOM_W=380
GEOM_H=240
STAMP="${XDG_RUNTIME_DIR:-/tmp}/powermenu-last-closed"

layer_present() {
  hyprctl layers -j 2>/dev/null \
    | jq -r '.[].levels | to_entries[] | .value[] | .namespace' \
    | grep -qx "eww-powermenu"
}

is_open() {
  "${EWW[@]}" active-windows 2>/dev/null | grep -q "^$WIN:" && return 0
  layer_present
}

force_recover() {
  pkill -KILL -f "^eww open powermenu" 2>/dev/null || true
  pkill -KILL -f "^eww .* open .*powermenu" 2>/dev/null || true
  pkill -KILL -x "eww" 2>/dev/null || true
  pkill -KILL -f "eww daemon" 2>/dev/null || true
  remove_outside_binds
  hyprctl dispatch submap reset >/dev/null 2>&1 || true
  rm -f /run/user/$(id -u)/eww-server_* 2>/dev/null
  setsid eww -c "$HOME/.config/eww" daemon >/dev/null 2>&1 &
  disown 2>/dev/null || true
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
  hyprctl dispatch submap powermenu >/dev/null
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
    lock)      hyprlock ;;
    suspend)   systemctl suspend ;;
    hibernate) systemctl hibernate ;;
    reboot)    systemctl reboot ;;
    poweroff)  systemctl poweroff ;;
    *) echo "unknown action: $1" >&2; return 1 ;;
  esac
}

case "${1:-toggle}" in
  toggle)
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
  close) close_menu ;;
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
  lock|suspend|hibernate|reboot|poweroff)
    run_action "$1"
    ;;
  panic) force_recover; "${EWW[@]}" close "$WIN" 2>/dev/null || true ;;
  *) echo "usage: $0 {toggle|close|outside-click|lock|suspend|hibernate|reboot|poweroff|panic}" >&2; exit 2 ;;
esac
