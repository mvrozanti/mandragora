#!/usr/bin/env bash
exec 200>/tmp/claude-spin-daemon.lock
flock -n 200 || exit 0
echo $$ > /tmp/claude-spin-daemon.pid
trap 'rm -f /tmp/claude-spin-daemon.pid' EXIT

declare -A scanned

turn_interrupted() {
  local key="$1|$2" transcript="$2" mark="${3:-0}" size from
  [ -f "$transcript" ] || return 1
  size=$(stat -c %s "$transcript")
  from=$(( ${scanned[$key]:-0} - 64 ))
  [ "$from" -lt "$mark" ] && from=$mark
  [ "$size" -gt "$from" ] || return 1
  scanned[$key]=$size
  tail -c +$((from + 1)) "$transcript" | grep -q '"text":"\[Request interrupted by user'
}

idle_rounds=0

while :; do
  tmux set -g @spin_glyph "$(claude-spin)" 2>/dev/null
  tmux refresh-client -S 2>/dev/null

  active=0
  while IFS=$'\t' read -r wid cmd state transcript mark; do
    [ "$state" = run ] && [ "$cmd" = claude ] || continue
    active=1
    if turn_interrupted "$wid" "$transcript" "$mark"; then
      tmux set-option -w -t "$wid" @claude_state idle 2>/dev/null
    fi
  done < <(tmux list-panes -a -F $'#{window_id}\t#{pane_current_command}\t#{@claude_state}\t#{@claude_transcript}\t#{@claude_mark}' 2>/dev/null)

  if [ "$active" -eq 0 ]; then
    idle_rounds=$((idle_rounds + 1))
    [ "$idle_rounds" -ge 5 ] && exit 0
  else
    idle_rounds=0
  fi
  sleep 0.1
done
