#!/usr/bin/env bash
state="${1:-}"
[ -n "$TMUX_PANE" ] || exit 0
[ -n "$state" ] || exit 0
if [ "$state" = "run" ]; then
  setsid claude-spin-daemon >/dev/null 2>&1 &
fi
if [ "$state" = "off" ]; then
  tmux set -w -u -t "$TMUX_PANE" @claude_state 2>/dev/null
else
  tmux set -w -t "$TMUX_PANE" @claude_state "$state" 2>/dev/null
fi
