#!/usr/bin/env bash
set -euo pipefail

state_dir="${XDG_RUNTIME_DIR:-/tmp}"
pidfile="$state_dir/screencap.pid"
outdir="$HOME/Videos"
mkdir -p "$outdir"

is_recording() {
  [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null
}

focused_monitor() {
  hyprctl -j monitors | jq -r '.[] | select(.focused) | .name'
}

default_sink_monitor() {
  local sink
  sink=$(pactl get-default-sink 2>/dev/null || echo "")
  [[ -n "$sink" ]] && echo "$sink.monitor"
}

start_record() {
  local target="$1"
  local region="${2:-}"
  local ts file sink args=()
  ts=$(date +%Y%m%d-%H%M%S)
  file="$outdir/screencap-$ts.mp4"
  sink=$(default_sink_monitor || true)

  if [[ -n "$region" ]]; then
    args=(-w region -region "$region" -f 60 -k h264 -q very_high -o "$file")
  else
    args=(-w "$target" -f 60 -k h264 -q very_high -o "$file")
  fi
  if [[ "${CAPTURE_NO_AUDIO:-0}" != "1" && -n "$sink" ]]; then
    args+=(-a "$sink")
  fi

  setsid gpu-screen-recorder "${args[@]}" >"$state_dir/screencap.log" 2>&1 &
  echo $! > "$pidfile"
  echo "$file" > "$state_dir/screencap.last"

  command -v notify-send >/dev/null && \
    notify-send -a screencap -i media-record "Recording started" "$(basename "$file")"

  pkill -RTMIN+11 waybar 2>/dev/null || true
}

stop_record() {
  if is_recording; then
    local pid
    pid=$(cat "$pidfile")
    kill -INT "$pid" 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.2
    done
    kill -TERM "$pid" 2>/dev/null || true
  fi
  rm -f "$pidfile"
  local last
  last=$(cat "$state_dir/screencap.last" 2>/dev/null || true)
  command -v notify-send >/dev/null && \
    notify-send -a screencap -i media-playback-stop "Recording saved" "${last:-done}"
  pkill -RTMIN+11 waybar 2>/dev/null || true
}

start_fullscreen() {
  start_record "$(focused_monitor)"
}

start_region() {
  local geom mon
  geom=$(slurp -f "%wx%h+%x+%y" -d) || return 0
  mon=$(focused_monitor)
  start_record "$mon" "$geom"
}

toggle_menu() {
  eww -c "$HOME/.config/eww" open --toggle capture-menu
}

case "${1:-status}" in
  fullscreen) eww -c "$HOME/.config/eww" close capture-menu 2>/dev/null || true; start_fullscreen ;;
  region)     eww -c "$HOME/.config/eww" close capture-menu 2>/dev/null || true; start_region ;;
  stop)       stop_record ;;
  toggle)
    if is_recording; then stop_record; else toggle_menu; fi
    ;;
  status)
    if is_recording; then
      printf '{"text":"󰑊","tooltip":"Recording — click to stop","class":"recording"}\n'
    else
      printf '{"text":"󰕧","tooltip":"Screen record","class":"idle"}\n'
    fi
    ;;
  *) echo "usage: $0 {fullscreen|region|stop|toggle|status}" >&2; exit 2 ;;
esac
