#!/usr/bin/env bash

state_dir="$HOME/.tmux/resurrect"
state_file="$state_dir/claude-sessions.tsv"
mode="${1:-}"

save() {
  mkdir -p "$state_dir"
  : > "$state_file"
  for pane_id in $(tmux list-panes -a -F '#{pane_id}'); do
    [ "$(tmux display-message -t "$pane_id" -p '#{pane_current_command}')" = claude ] || continue
    tty="$(tmux display-message -t "$pane_id" -p '#{pane_tty}')"
    sess="$(tmux display-message -t "$pane_id" -p '#{session_name}')"
    win="$(tmux display-message -t "$pane_id" -p '#{window_index}')"
    idx="$(tmux display-message -t "$pane_id" -p '#{pane_index}')"
    cwd="$(tmux display-message -t "$pane_id" -p '#{pane_current_path}')"
    for p in $(pgrep -x claude); do
      [ "$(readlink "/proc/${p}/fd/0" 2>/dev/null)" = "$tty" ] || continue
      path="$(ls -l "/proc/${p}/fd/" 2>/dev/null | grep -oE '/tmp/claude-[0-9]+/[^ ]+' | head -n1)"
      [ -n "$path" ] || continue
      sid="$(basename "$(dirname "$path")")"
      printf '%s\t%s\t%s\t%s\t%s\n' "$sess" "$win" "$idx" "$cwd" "$sid" >> "$state_file"
      break
    done
  done
}

restore() {
  [ -f "$state_file" ] || return 0
  while IFS=$'\t' read -r sess win idx cwd sid; do
    [ -n "${sess}${sid}" ] || continue
    tmux respawn-pane -k -t "${sess}:${win}.${idx}" -c "$cwd" "claude --resume '${sid}'" 2>/dev/null
  done < "$state_file"
}

case "$mode" in
  save) save ;;
  restore) restore ;;
esac
