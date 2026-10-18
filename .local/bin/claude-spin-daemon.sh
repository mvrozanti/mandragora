#!/usr/bin/env bash
exec 200>/tmp/claude-spin-daemon.lock
flock -n 200 || exit 0
echo $$ > /tmp/claude-spin-daemon.pid
trap 'rm -f /tmp/claude-spin-daemon.pid' EXIT

pane_claude_pid() {
  local p
  [ "$(cat /proc/$1/comm 2>/dev/null)" = "claude" ] && { echo "$1"; return 0; }
  for p in $(cat /proc/$1/task/*/children 2>/dev/null | tr ' ' '\n'); do
    [ -n "$p" ] || continue
    [ "$(cat /proc/$p/comm 2>/dev/null)" = "claude" ] && { echo "$p"; return 0; }
  done
  return 1
}

claude_running_tool() {
  local c t
  for c in $(cat /proc/$1/task/*/children 2>/dev/null | tr ' ' '\n'); do
    [ -n "$c" ] || continue
    t=$(readlink /proc/$c/fd/1 2>/dev/null)
    case "$t" in
      */tasks/*.output*) return 0 ;;
    esac
  done
  return 1
}

declare -A ticks
idle_rounds=0

while :; do
  tmux set -g @spin_glyph "$(claude-spin)" 2>/dev/null
  tmux refresh-client -S 2>/dev/null

  active=0
  while IFS=' ' read -r wid pane state; do
    [ "$state" = run ] || continue
    active=1
    cpid=$(pane_claude_pid "$pane")
    if [ -n "$cpid" ] && claude_running_tool "$cpid"; then
      ticks[$wid]=0
      continue
    fi
    ticks[$wid]=$(( ${ticks[$wid]:-0} + 1 ))
    if [ "${ticks[$wid]}" -ge 5 ]; then
      tmux set-option -w -t "$wid" @claude_state idle 2>/dev/null
      unset "ticks[$wid]"
    fi
  done < <(tmux list-windows -a -F '#{window_id} #{pane_pid} #{@claude_state}' 2>/dev/null)

  if [ "$active" -eq 0 ]; then
    idle_rounds=$((idle_rounds + 1))
    [ "$idle_rounds" -ge 5 ] && exit 0
  else
    idle_rounds=0
  fi
  sleep 0.1
done
