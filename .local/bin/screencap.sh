#!/usr/bin/env bash
set -euo pipefail

state_dir="${XDG_RUNTIME_DIR:-/tmp}"
pidfile="$state_dir/screencap.pid"
audiofile="$state_dir/screencap.audio"
startfile="$state_dir/screencap.start"
status_file="/tmp/recording_status"
outdir="$HOME/Videos"
mkdir -p "$outdir"

is_recording() {
  [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null
}

write_idle() { echo "idle" > "$status_file"; }
write_recording() { echo "recording:$1:$2" > "$status_file"; }

monitors_json() { hyprctl -j monitors; }

monitors_list() { monitors_json | jq -r '.[].name'; }

monitor_count() { monitors_json | jq 'length'; }

focused_monitor() { monitors_json | jq -r '.[] | select(.focused) | .name'; }

spanned_geometry() {
  monitors_json | jq -r '
    [.[] | {x: .x, y: .y, w: .width, h: .height}] as $m
    | ([$m[].x] | min) as $minx
    | ([$m[].y] | min) as $miny
    | ([$m[] | (.x + .w)] | max) as $maxx
    | ([$m[] | (.y + .h)] | max) as $maxy
    | "\($minx),\($miny) \($maxx - $minx)x\($maxy - $miny)"
  '
}

default_sink_monitor() {
  local sink
  sink=$(pactl get-default-sink 2>/dev/null || echo "")
  [[ -n "$sink" ]] && echo "$sink.monitor"
}

default_mic_source() {
  local default_src
  default_src=$(pactl get-default-source 2>/dev/null || echo "")
  if [[ -n "$default_src" && "$default_src" != *.monitor ]]; then
    echo "$default_src"
    return
  fi
  pactl -f json list sources 2>/dev/null \
    | jq -r '.[] | select(.name | endswith(".monitor") | not) | .name' \
    | head -n1
}

has_mic() { [[ -n "$(default_mic_source)" ]]; }

choose_monitor() {
  local count names choice
  count=$(monitor_count)
  if (( count <= 1 )); then
    echo "monitor:$(focused_monitor)"
    return
  fi
  names=$(monitors_list)
  choice=$(printf 'All monitors\n%s\n' "$names" | rofi -dmenu -i -p "Capture monitor:" 2>/dev/null) || return 0
  [[ -z "$choice" ]] && return 0
  if [[ "$choice" == "All monitors" ]]; then
    echo "region:$(spanned_geometry)"
  else
    echo "monitor:$choice"
  fi
}

slurp_geom() {
  slurp -f "%x,%y %wx%h" -d 2>/dev/null || true
}

start_record() {
  local audio_mode="$1" target="$2"
  local ts file args src now
  ts=$(date +%Y%m%d-%H%M%S)
  file="$outdir/screencap-$ts.mp4"
  args=(-c libx264 -C aac -p preset=veryfast -p crf=20 -f "$file")
  case "$target" in
    monitor:*) args+=(-o "${target#monitor:}") ;;
    region:*)  args+=(-g "${target#region:}") ;;
    *) echo "bad target: $target" >&2; return 1 ;;
  esac
  case "$audio_mode" in
    mic)
      src=$(default_mic_source)
      [[ -n "$src" ]] && args+=("--audio=$src")
      ;;
    system)
      src=$(default_sink_monitor)
      [[ -n "$src" ]] && args+=("--audio=$src")
      ;;
  esac

  setsid wf-recorder "${args[@]}" >"$state_dir/screencap.log" 2>&1 &
  echo $! > "$pidfile"
  echo "$file" > "$state_dir/screencap.last"
  echo "$audio_mode" > "$audiofile"
  now=$(date +%s)
  echo "$now" > "$startfile"
  write_recording "$audio_mode" "$now"

  command -v notify-send >/dev/null && \
    notify-send -a screencap -i media-record "Recording started" \
      "Audio: $audio_mode"$'\n'"$(basename "$file")"

  pkill -RTMIN+11 waybar 2>/dev/null || true
}

stop_record() {
  local last audio
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
  last=$(cat "$state_dir/screencap.last" 2>/dev/null || true)
  audio=$(cat "$audiofile" 2>/dev/null || echo "none")
  rm -f "$pidfile" "$audiofile" "$startfile"
  write_idle
  command -v notify-send >/dev/null && \
    notify-send -a screencap -i media-playback-stop "Recording saved" \
      "Audio: $audio"$'\n'"${last:-done}"
  pkill -RTMIN+11 waybar 2>/dev/null || true
}

flashfile="$state_dir/screencap.flash"

mark_flash() {
  date +%s > "$flashfile"
  pkill -RTMIN+11 waybar 2>/dev/null || true
}

preview_max_w=480
preview_max_h=360
preview_timeout=3
preview_eww_cfg="$HOME/.config/eww"
preview_window=screencap-preview

ensure_eww_daemon() {
  if pgrep -x eww >/dev/null 2>&1; then
    local sock; sock=$(ls /run/user/$(id -u)/eww-server_* 2>/dev/null | head -1)
    [[ -S "$sock" ]] && return 0
  fi
  setsid eww -c "$preview_eww_cfg" daemon >/dev/null 2>&1 &
  for _ in $(seq 1 60); do
    local sock; sock=$(ls /run/user/$(id -u)/eww-server_* 2>/dev/null | head -1)
    [[ -S "$sock" ]] && return 0
    sleep 0.025
  done
  return 1
}

preview_image() {
  local file="$1"
  command -v eww >/dev/null || return 0
  command -v identify >/dev/null || return 0
  ensure_eww_daemon || return 0
  local dims w h scale_w scale_h scale tw th
  dims=$(identify -format '%wx%h' "$file" 2>/dev/null) || return 0
  w=${dims%x*}; h=${dims#*x}
  [[ -z "$w" || -z "$h" || "$w" -le 0 || "$h" -le 0 ]] && return 0
  scale_w=$((preview_max_w * 1000 / w))
  scale_h=$((preview_max_h * 1000 / h))
  scale=$(( scale_w < scale_h ? scale_w : scale_h ))
  (( scale > 1000 )) && scale=1000
  tw=$(( w * scale / 1000 ))
  th=$(( h * scale / 1000 ))
  eww -c "$preview_eww_cfg" update \
    "screencap-preview-path=$file" \
    "screencap-preview-w=$tw" \
    "screencap-preview-h=$th" >/dev/null 2>&1 || return 0
  eww -c "$preview_eww_cfg" open --toggle "$preview_window" >/dev/null 2>&1 || \
    eww -c "$preview_eww_cfg" open "$preview_window" >/dev/null 2>&1
  ( sleep "$preview_timeout"
    eww -c "$preview_eww_cfg" close "$preview_window" >/dev/null 2>&1
  ) &
  disown 2>/dev/null || true
}

screenshot_full() {
  local target file
  target=$(choose_monitor)
  [[ -z "$target" ]] && return 0
  file="$outdir/screenshot-$(date +%Y%m%d-%H%M%S).png"
  case "$target" in
    monitor:*) grim -o "${target#monitor:}" "$file" ;;
    region:*)  grim -g "${target#region:}" "$file" ;;
  esac
  wl-copy < "$file"
  preview_image "$file"
  mark_flash
}

screenshot_region() {
  local file tmp
  file="$outdir/screenshot-$(date +%Y%m%d-%H%M%S).png"
  tmp=$(mktemp --suffix=.png)
  flameshot gui --raw 2>/dev/null > "$tmp" || true
  if [[ ! -s "$tmp" ]]; then
    rm -f "$tmp"
    return 0
  fi
  mv "$tmp" "$file"
  wl-copy --type image/png < "$file"
  preview_image "$file"
  mark_flash
}

active_window_geom() {
  hyprctl -j activewindow | jq -r 'select(.at != null) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"'
}

screenshot_window() {
  local geom file
  geom=$(active_window_geom)
  [[ -z "$geom" ]] && return 0
  file="$outdir/screenshot-$(date +%Y%m%d-%H%M%S).png"
  grim -g "$geom" "$file"
  wl-copy --type image/png < "$file"
  preview_image "$file"
  mark_flash
}

video_full() {
  local audio="$1" target
  target=$(choose_monitor)
  [[ -z "$target" ]] && return 0
  start_record "$audio" "$target"
}

video_region() {
  local audio="$1" geom
  geom=$(slurp_geom)
  [[ -z "$geom" ]] && return 0
  start_record "$audio" "region:$geom"
}

video_window() {
  local audio="$1" geom
  geom=$(active_window_geom)
  [[ -z "$geom" ]] && return 0
  start_record "$audio" "region:$geom"
}

elapsed_hms() {
  local start now diff
  start=$(cat "$startfile" 2>/dev/null || echo 0)
  [[ "$start" -le 0 ]] && { echo "00:00:00"; return; }
  now=$(date +%s)
  diff=$(( now - start ))
  printf "%02d:%02d:%02d\n" $((diff/3600)) $(((diff%3600)/60)) $((diff%60))
}

flash_active() {
  local f now
  f=$(cat "$flashfile" 2>/dev/null || echo 0)
  now=$(date +%s)
  (( now - f <= 1 ))
}

status_json() {
  if is_recording; then
    local audio elapsed icon tip
    audio=$(cat "$audiofile" 2>/dev/null || echo "none")
    elapsed=$(elapsed_hms)
    case "$audio" in
      mic)    icon="󰍬"; tip="Recording (mic)" ;;
      system) icon="󰓃"; tip="Recording (system audio)" ;;
      *)      icon="󰕧"; tip="Recording (no audio)" ;;
    esac
    printf '{"text":"<span color=\"#ff3b30\">⏺</span> %s %s","tooltip":"%s — right-click to stop","class":"recording %s"}\n' \
      "$icon" "$elapsed" "$tip" "$audio"
  elif flash_active; then
    printf '{"text":"󰄄","tooltip":"Screenshot captured","class":"idle flash"}\n'
  else
    printf '{"text":"󰄀","tooltip":"Screen capture — left-click for menu, right-click to stop recording","class":"idle"}\n'
  fi
}

case "${1:-status}" in
  shot-region)     screenshot_region ;;
  shot-full)       screenshot_full ;;
  shot-window)     screenshot_window ;;
  vid-none-region) video_region none ;;
  vid-none-full)   video_full none ;;
  vid-none-window) video_window none ;;
  vid-mic-region)  video_region mic ;;
  vid-mic-full)    video_full mic ;;
  vid-mic-window)  video_window mic ;;
  vid-sys-region)  video_region system ;;
  vid-sys-full)    video_full system ;;
  vid-sys-window)  video_window system ;;
  stop)            stop_record ;;
  has-mic)         has_mic && echo yes || echo no ;;
  is-recording)    is_recording && echo yes || echo no ;;
  status)          status_json ;;
  *) echo "usage: $0 {shot-region|shot-full|shot-window|vid-{none,mic,sys}-{region,full,window}|stop|has-mic|is-recording|status}" >&2; exit 2 ;;
esac
