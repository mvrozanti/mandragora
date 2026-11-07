#!/usr/bin/env bash
state="${1:-}"
[ -n "$TMUX_PANE" ] || exit 0
[ -n "$state" ] || exit 0
input=""
[ -t 0 ] || input=$(cat)
IFS=$'\t' read -r event tool agent transcript < <(
  jq -r '[.hook_event_name // "", .tool_name // "", .agent_id // "", .transcript_path // ""] | @tsv' <<<"$input" 2>/dev/null
)
[ -n "$agent" ] && exit 0
if [ "$event" = PreToolUse ]; then
  case "$tool" in
    AskUserQuestion|ExitPlanMode) state=idle ;;
  esac
fi
if [ "$state" = "off" ]; then
  tmux set -w -u -t "$TMUX_PANE" @claude_state 2>/dev/null
elif [ "$state" = "run" ] && [ -f "$transcript" ]; then
  tmux set -w -t "$TMUX_PANE" @claude_transcript "$transcript" \; \
    set -w -t "$TMUX_PANE" @claude_mark "$(stat -c %s "$transcript")" \; \
    set -w -t "$TMUX_PANE" @claude_state run 2>/dev/null
else
  tmux set -w -t "$TMUX_PANE" @claude_state "$state" 2>/dev/null
fi
if [ "$state" = "run" ]; then
  setsid claude-spin-daemon >/dev/null 2>&1 &
fi
if [ "$state" != "run" ] && ! tmux list-windows -a -F '#{@claude_state}' 2>/dev/null | grep -qx run; then
  [ -f /tmp/claude-spin-daemon.pid ] && kill "$(cat /tmp/claude-spin-daemon.pid)" 2>/dev/null
fi
exit 0
