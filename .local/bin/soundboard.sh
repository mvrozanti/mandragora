#!/usr/bin/env bash
set -euo pipefail

SB_DIR="${SOUNDBOARD_DIR:-$HOME/.local/share/soundboard}"
PIDFILE="${XDG_RUNTIME_DIR:-/tmp}/soundboard.pids"
TARGET="Soundboard"

play() {
  local f="$1"
  [[ -f "$f" ]] || f="$SB_DIR/$f"
  if [[ ! -f "$f" ]]; then
    notify-send "Soundboard" "not found: $1"
    exit 1
  fi
  mpv --no-terminal --no-config --vid=no --vo=null --force-window=no \
      --keep-open=no --idle=no --really-quiet \
      --audio-device="pipewire/$TARGET" "$f" &
  echo $! >>"$PIDFILE"
}

stop() {
  [[ -f "$PIDFILE" ]] || return 0
  while read -r pid; do
    kill "$pid" 2>/dev/null || true
  done <"$PIDFILE"
  : >"$PIDFILE"
}

case "${1:-menu}" in
  stop)
    stop
    ;;
  slot)
    n="${2:-}"
    [[ -n "$n" ]] || { notify-send "Soundboard" "usage: soundboard slot N"; exit 1; }
    f=$(find "$SB_DIR/slots" -maxdepth 1 -type f -name "$n.*" 2>/dev/null | head -1)
    if [[ -z "$f" ]]; then
      notify-send "Soundboard" "empty slot $n"
      exit 1
    fi
    stop
    play "$f"
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
