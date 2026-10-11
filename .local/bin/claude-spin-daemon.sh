#!/usr/bin/env bash
exec 200>/tmp/claude-spin-daemon.lock
flock -n 200 || exit 0
while :; do
  if tmux list-windows -a -F '#{@claude_state}' 2>/dev/null | grep -qx run; then
    tmux set -g @spin_glyph "$(claude-spin)" 2>/dev/null
    tmux refresh-client -S 2>/dev/null
  fi
  sleep 0.1
done
