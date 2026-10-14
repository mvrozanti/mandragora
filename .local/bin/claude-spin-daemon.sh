#!/usr/bin/env bash
exec 200>/tmp/claude-spin-daemon.lock
flock -n 200 || exit 0
echo $$ > /tmp/claude-spin-daemon.pid
trap 'rm -f /tmp/claude-spin-daemon.pid' EXIT
claude_running_tool() {
  local p c t
  for p in $(pgrep -x claude 2>/dev/null); do
    for c in $(cat /proc/$p/task/*/children 2>/dev/null | tr ' ' '\n'); do
      [ -n "$c" ] || continue
      t=$(readlink /proc/$c/fd/1 2>/dev/null)
      case "$t" in
        */tasks/*.output*) return 0 ;;
      esac
    done
  done
  return 1
}

idle=0
while :; do
  tmux set -g @spin_glyph "$(claude-spin)" 2>/dev/null
  tmux refresh-client -S 2>/dev/null
  if claude_running_tool; then
    idle=0
  else
    idle=$((idle + 1))
  fi
  if [ "$idle" -ge 5 ]; then
    while IFS= read -r line; do
      case "$line" in
        *' run') tmux set-option -w -t "${line%% *}" @claude_state idle 2>/dev/null ;;
      esac
    done < <(tmux list-windows -a -F '#{window_id} #{@claude_state}' 2>/dev/null)
    exit 0
  fi
  sleep 0.1
done
