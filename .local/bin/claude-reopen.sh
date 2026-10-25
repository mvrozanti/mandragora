#!/usr/bin/env bash
set -euo pipefail

sid="${1:?session id}"
cwd="${2:-$HOME}"
title="${3:-}"

[ -d "$cwd" ] || {
    echo "claude-reopen: $cwd is gone, opening in $HOME" >&2
    cwd="$HOME"
}

window_name="${title:-claude-${sid:0:8}}"
window_name="${window_name:0:28}"

if [ -n "${TMUX:-}" ]; then
    tmux new-window -c "$cwd" -n "$window_name" "exec claude --resume '$sid'"
else
    cd "$cwd"
    exec claude --resume "$sid"
fi
