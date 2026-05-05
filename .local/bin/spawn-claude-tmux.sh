#!/usr/bin/env bash
set -euo pipefail

cwd="${1:-$HOME}"
if [ ! -d "$cwd" ]; then
    echo "spawn-claude-tmux: directory does not exist: $cwd" >&2
    exit 1
fi

session="$(tmux list-sessions -F '#{session_name}' 2>/dev/null | head -n1 || true)"
if [ -z "$session" ]; then
    echo "spawn-claude-tmux: no tmux server / session running" >&2
    exit 1
fi

window_name="claude-$(date +%H%M%S)"

tmux new-window -t "${session}:" -n "$window_name" -c "$cwd" "exec claude"

echo "spawned '${window_name}' in tmux session '${session}' (cwd: ${cwd}). attach via the Claude app."
