#!/usr/bin/env bash
set -u

pad=_scratch

pad_ids() {
  tmux list-windows -t "$pad" -F '#{window_id}' 2>/dev/null
}

current_window() {
  tmux display-message -p '#{window_id}'
}

resolve_window() {
  tmux display-message -p -t "$1" '#{window_id}' 2>/dev/null
}

unmark() {
  tmux set-option -w -u -t "$1" @scratchpad 2>/dev/null || true
}

mark() {
  tmux set-option -w -t "$1" @scratchpad 1
}

marked() {
  [ "$(tmux show-options -w -qv -t "$1" @scratchpad 2>/dev/null)" = 1 ]
}

stash() {
  local win=$1 edge=$2 boot
  if tmux has-session -t "$pad" 2>/dev/null; then
    if [ "$edge" = front ]; then
      tmux move-window -b -s "$win" -t "$(pad_ids | head -n1)"
    else
      tmux move-window -a -s "$win" -t "$(pad_ids | tail -n1)"
    fi
  else
    tmux new-session -d -s "$pad" \
      -x "$(tmux display-message -p -t "$win" '#{window_width}')" \
      -y "$(tmux display-message -p -t "$win" '#{window_height}')"
    boot=$(pad_ids | head -n1)
    tmux move-window -a -s "$win" -t "$boot"
    tmux kill-window -t "$boot"
  fi
  unmark "$win"
}

cmd_hide() {
  local win session
  win=$(current_window)
  session=$(tmux display-message -p -t "$win" '#{session_name}')
  if [ "$(tmux list-windows -t "$session" | wc -l)" -le 1 ]; then
    tmux display-message "scratchpad: refusing to stash the session's last window"
    return 1
  fi
  stash "$win" back
}

cmd_summon() {
  local target=${1:-} cur
  [ -n "$target" ] && target=$(resolve_window "$target")
  [ -z "$target" ] && target=$(pad_ids | tail -n1)
  if [ -z "$target" ]; then
    tmux display-message "scratchpad: empty"
    return 1
  fi
  cur=$(current_window)
  tmux move-window -a -s "$target" -t "$cur"
  mark "$target"
  tmux select-window -t "$target"
}

cmd_cycle() {
  local cur next
  cur=$(current_window)
  if ! marked "$cur"; then
    cmd_summon
    return
  fi
  next=$(pad_ids | tail -n1)
  if [ -z "$next" ]; then
    tmux display-message "scratchpad: nothing else stashed"
    return 0
  fi
  tmux move-window -a -s "$next" -t "$cur"
  mark "$next"
  tmux select-window -t "$next"
  stash "$cur" front
}

cmd_count() {
  local n
  n=$(pad_ids | wc -l)
  [ "$n" -gt 0 ] && printf '[%s] ' "$n"
  return 0
}

case ${1:-} in
  hide) cmd_hide ;;
  summon) cmd_summon "${2:-}" ;;
  cycle) cmd_cycle ;;
  count) cmd_count ;;
  list) pad_ids ;;
  *)
    echo "usage: tmux-scratchpad {hide|summon [window]|cycle|count|list}" >&2
    exit 2
    ;;
esac
