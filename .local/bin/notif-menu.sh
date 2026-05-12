#!/usr/bin/env bash
set -euo pipefail

EWW=(eww -c "$HOME/.config/eww")
WIN=notif-menu
SELF="$HOME/.local/bin/notif-menu"
GEOM_X=12
GEOM_Y=56
GEOM_W=440
GEOM_H=560
STAMP="${XDG_RUNTIME_DIR:-/tmp}/notif-menu-last-closed"

layer_present() {
  hyprctl layers -j 2>/dev/null \
    | jq -r '.[].levels | to_entries[] | .value[] | .namespace' \
    | grep -qx "eww-notif-menu"
}

is_open() {
  "${EWW[@]}" active-windows 2>/dev/null | grep -q "^$WIN:" && return 0
  layer_present
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

force_recover() {
  pkill -KILL -f "^eww .* open .*notif-menu" 2>/dev/null || true
  remove_outside_binds
  hyprctl dispatch submap reset >/dev/null 2>&1 || true
}

emit_json() {
  makoctl history -j 2>/dev/null | jq -c '
    def trim(s): if (s|length) > 240 then (s[0:237] + "...") else s end;
    def squish(s): (s // "") | gsub("[\r\n\t]+"; " ") | gsub(" +"; " ");
    def cls(u):
      if   u == 2 then "critical"
      elif u == 0 then "low"
      else "normal" end;
    reverse | map({
      id: .id,
      app: ((.app_name // "?") | squish),
      summary: (.summary | squish | trim(.)),
      body: (.body | squish | trim(.)),
      urgency_cls: cls(.urgency)
    })
  '
}

emit_dnd_status() {
  if makoctl mode 2>/dev/null | grep -qx do-not-disturb; then
    echo on
  else
    echo off
  fi
}

emit_count() {
  makoctl history -j 2>/dev/null | jq 'length'
}

refresh_state() {
  local json dnd
  json=$(emit_json)
  dnd=$(emit_dnd_status)
  "${EWW[@]}" update "notif-history=$json" "notif-dnd=$dnd" >/dev/null 2>&1 || true
}

open_menu() {
  ensure_daemon
  refresh_state
  "${EWW[@]}" open "$WIN"
  hyprctl dispatch submap notif-menu >/dev/null
  install_outside_binds
}

close_menu() {
  remove_outside_binds
  hyprctl dispatch submap reset >/dev/null 2>&1 || true
  "${EWW[@]}" close "$WIN" 2>/dev/null || true
  date +%s%N > "$STAMP"
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
  json) emit_json ;;
  dnd-status) emit_dnd_status ;;
  count) emit_count ;;
  refresh) refresh_state ;;
  dismiss)
    id="${2:-}"
    [[ -z "$id" ]] && { echo "usage: $0 dismiss <id>" >&2; exit 2; }
    makoctl dismiss -n "$id" >/dev/null 2>&1 || true
    refresh_state
    ;;
  invoke)
    id="${2:-}"
    [[ -z "$id" ]] && { echo "usage: $0 invoke <id>" >&2; exit 2; }
    makoctl invoke -n "$id" default >/dev/null 2>&1 || true
    close_menu
    ;;
  clear)
    makoctl dismiss --all >/dev/null 2>&1 || true
    refresh_state
    ;;
  dnd)
    if makoctl mode 2>/dev/null | grep -qx do-not-disturb; then
      makoctl mode -r do-not-disturb >/dev/null
      notify-send -t 1500 "Notifications" "Do Not Disturb: off"
    else
      notify-send -t 1500 "Notifications" "Do Not Disturb: on"
      makoctl mode -a do-not-disturb >/dev/null
    fi
    refresh_state
    ;;
  panic) force_recover; "${EWW[@]}" close "$WIN" 2>/dev/null || true ;;
  *) echo "usage: $0 {toggle|close|outside-click|json|dnd-status|count|refresh|dismiss <id>|invoke <id>|clear|dnd|panic}" >&2; exit 2 ;;
esac
