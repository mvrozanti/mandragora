#!/usr/bin/env bash
set -euo pipefail

is_recording() { [[ "$(screencap is-recording 2>/dev/null || echo no)" == yes ]]; }

case "${1:-toggle}" in
  toggle)
    if is_recording; then
      exec screencap stop
    fi
    exec rofi-capture-menu
    ;;
  close)
    pkill -x rofi 2>/dev/null || true
    ;;
  shot-region|shot-full|shot-window|vid-none-region|vid-none-full|vid-none-window|vid-mic-region|vid-mic-full|vid-mic-window|vid-sys-region|vid-sys-full|vid-sys-window)
    exec screencap "$1"
    ;;
  stop)
    exec screencap stop
    ;;
  *)
    echo "usage: $0 {toggle|close|shot-{region,full,window}|vid-{none,mic,sys}-{region,full,window}|stop}" >&2
    exit 2
    ;;
esac
