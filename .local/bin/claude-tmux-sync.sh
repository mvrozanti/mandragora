#!/usr/bin/env bash
set -euo pipefail

state_dir="${HOME}/.claude/tmux-sync"
names_dir="${state_dir}/names"
panes_dir="${state_dir}/panes"
mkdir -p "${names_dir}" "${panes_dir}"

cmd="${1:-}"
shift || true

read_session_id() {
  jq -r '.session_id // empty'
}

case "$cmd" in
  claude-start)
    if [ -z "${TMUX_PANE:-}" ]; then exit 0; fi
    session_id=$(read_session_id)
    if [ -z "$session_id" ]; then exit 0; fi
    printf '%s' "$session_id" > "${panes_dir}/${TMUX_PANE}"
    name_file="${names_dir}/${session_id}"
    if [ -s "$name_file" ]; then
      name=$(cat "$name_file")
    else
      name="claude:${session_id:0:6}"
      printf '%s' "$name" > "$name_file"
    fi
    tmux rename-window -t "$TMUX_PANE" "$name" 2>/dev/null || true
    ;;
  claude-end)
    if [ -z "${TMUX_PANE:-}" ]; then exit 0; fi
    rm -f "${panes_dir}/${TMUX_PANE}"
    ;;
  tmux-renamed)
    pane_id="${1:-}"
    name="${2:-}"
    if [ -z "$pane_id" ]; then exit 0; fi
    pane_file="${panes_dir}/${pane_id}"
    if [ ! -s "$pane_file" ]; then exit 0; fi
    session_id=$(cat "$pane_file")
    printf '%s' "$name" > "${names_dir}/${session_id}"
    ;;
  *)
    echo "usage: claude-tmux-sync {claude-start|claude-end|tmux-renamed <pane_id> <name>}" >&2
    exit 2
    ;;
esac
