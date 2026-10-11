#!/usr/bin/env bash
exec 200>/tmp/claude-spin-daemon.lock
flock -n 200 || exit 0
echo $$ > /tmp/claude-spin-daemon.pid
trap 'rm -f /tmp/claude-spin-daemon.pid' EXIT
while :; do
  tmux set -g @spin_glyph "$(claude-spin)" 2>/dev/null
  tmux refresh-client -S 2>/dev/null
  sleep 0.1
done
