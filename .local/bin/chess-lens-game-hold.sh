#!/usr/bin/env bash
set -u

hold="${CHESS_LENS_HOLD_FILE:?}"
unit="${CHESS_LENS_UNIT:-chess-lens-backend.service}"
quota="${GAME_HOLD_CPU_QUOTA:-100%}"
marker="${GAME_HOLD_MARKER:-SteamLaunch}"
poll="${GAME_HOLD_POLL_SECONDS:-2}"

game_running() {
  local pid
  for pid in $(pgrep -x reaper); do
    grep -qaF -- "$marker" "/proc/$pid/cmdline" 2>/dev/null && return 0
  done
  return 1
}

raise() {
  mkdir -p "${hold%/*}"
  : >"$hold"
  if systemctl --user set-property --runtime "$unit" CPUQuota="$quota"; then
    echo "game running: chess-lens held, $unit capped at $quota"
  else
    echo "game running: chess-lens held, but capping $unit at $quota FAILED" >&2
  fi
}

lower() {
  rm -f "$hold"
  if systemctl --user set-property --runtime "$unit" CPUQuota=; then
    echo "no game: chess-lens released"
  else
    echo "no game: chess-lens released, but lifting the cap on $unit FAILED" >&2
  fi
}

if [ "${1:-}" = lower ]; then
  lower
  exit 0
fi

trap 'lower; exit 0' TERM INT

state=unknown
while :; do
  if game_running; then
    [ "$state" = held ] || { raise; state=held; }
  else
    [ "$state" = free ] || { lower; state=free; }
  fi
  sleep "$poll" &
  wait $!
done
