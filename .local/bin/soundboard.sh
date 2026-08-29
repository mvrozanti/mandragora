#!/usr/bin/env bash
set -euo pipefail

SB_DIR="${SOUNDBOARD_DIR:-$HOME/.local/share/soundboard}"
PIDFILE="${XDG_RUNTIME_DIR:-/tmp}/soundboard.pids"
TARGET="Soundboard"
PTT="${SOUNDBOARD_PTT:-1}"
PTT_KEY="${SOUNDBOARD_PTT_KEY:-100}"

ptt_play() {
  local f="$1" vol="${2:-100}" mpv_pid=""
  release_ptt() { [[ "$PTT" == 1 ]] && ydotool key "${PTT_KEY}:0" 2>/dev/null || true; }
  trap 'kill "$mpv_pid" 2>/dev/null || true; release_ptt; exit 0' TERM INT
  [[ "$PTT" == 1 ]] && ydotool key "${PTT_KEY}:1" 2>/dev/null || true
  mpv --no-terminal --no-config --vid=no --vo=null --force-window=no \
      --keep-open=no --idle=no --really-quiet --volume="$vol" \
      --audio-device="pipewire/$TARGET" "$f" &
  mpv_pid=$!
  wait "$mpv_pid" 2>/dev/null || true
  release_ptt
}

play() {
  local f="$1" vol="${2:-100}"
  [[ -f "$f" ]] || f="$SB_DIR/$f"
  if [[ ! -f "$f" ]]; then
    notify-send "Soundboard" "not found: $1"
    exit 1
  fi
  ptt_play "$f" "$vol" &
  echo $! >>"$PIDFILE"
}

stop() {
  [[ -f "$PIDFILE" ]] || return 0
  local pids=()
  while read -r pid; do
    [[ -n "$pid" ]] || continue
    kill "$pid" 2>/dev/null || true
    pids+=("$pid")
  done <"$PIDFILE"
  : >"$PIDFILE"
  for pid in "${pids[@]}"; do
    for _ in $(seq 1 50); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.02
    done
  done
}

case "${1:-menu}" in
  stop)
    stop
    ;;
  slot)
    n="${2:-}"
    vol="${3:-100}"
    [[ -n "$n" ]] || { notify-send "Soundboard" "usage: soundboard slot N"; exit 1; }
    f=$(find "$SB_DIR/slots" -maxdepth 1 -type f -name "$n.*" 2>/dev/null | head -1)
    if [[ -z "$f" ]]; then
      notify-send "Soundboard" "empty slot $n"
      exit 1
    fi
    stop
    play "$f" "$vol"
    ;;
  menu)
    mapfile -t files < <(find "$SB_DIR" -type f \
      \( -iname '*.wav' -o -iname '*.mp3' -o -iname '*.ogg' \
         -o -iname '*.flac' -o -iname '*.opus' -o -iname '*.m4a' \) \
      -printf '%P\n' 2>/dev/null | sort)
    if [[ ${#files[@]} -eq 0 ]]; then
      notify-send "Soundboard" "no sounds in $SB_DIR"
      exit 0
    fi
    sel=$(printf '⏹  Stop all\n%s\n' "${files[@]}" | rofi -dmenu -i -p "Soundboard" \
          -theme "$HOME/.config/rofi/themes/menu.rasi") || exit 0
    case "$sel" in
      "") exit 0 ;;
      "⏹  Stop all") stop ;;
      *) play "$sel" ;;
    esac
    ;;
  *)
    play "$1"
    ;;
esac
