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
STATE_FILE="$HOME/.config/eww/.capture-selected"

ACTIONS=(shot-region shot-full vid-none-region vid-none-full vid-mic-region vid-mic-full vid-sys-region vid-sys-full)

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
  echo 0 > "$STATE_FILE"
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

step_index() {
  local dir="$1" curr next
  curr=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
  next=$curr
  for _ in 1 2 3 4 5 6 7 8; do
    next=$(( (next + dir + 8) % 8 ))
    if ! is_disabled "${ACTIONS[$next]}"; then
      echo "$next" > "$STATE_FILE"
      return
    fi
  done
}

select_current() {
  local curr action
  curr=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
  action="${ACTIONS[$curr]}"
  is_disabled "$action" && return 0
  "$SELF" "$action"
}

run_action() {
  close_menu
  case "$1" in
    shot-region|shot-full|vid-none-region|vid-none-full|vid-mic-region|vid-mic-full|vid-sys-region|vid-sys-full)
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
  next) step_index 1 ;;
  prev) step_index -1 ;;
  select) select_current ;;
  shot-region|shot-full|vid-none-region|vid-none-full|vid-mic-region|vid-mic-full|vid-sys-region|vid-sys-full)
    run_action "$1"
    ;;
  stop) close_menu; screencap stop ;;
  panic) force_recover; "${EWW[@]}" close "$WIN" 2>/dev/null || true ;;
  *) echo "usage: $0 {toggle|close|outside-click|next|prev|select|shot-region|shot-full|vid-{none,mic,sys}-{region,full}|stop|panic}" >&2; exit 2 ;;
esac
