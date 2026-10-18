#!/usr/bin/env bash
set -uo pipefail

pane="${1:?pane id}"
pane_pid="${2:?pane pid}"

stat=$(cat "/proc/$pane_pid/stat" 2>/dev/null) || exit 0
read -r _ _ _ _ _ foreground_pgid _ <<<"${stat##*) }"

backend=""
if tr '\0' '\n' <"/proc/$foreground_pgid/environ" 2>/dev/null \
    | grep -q '^ANTHROPIC_BASE_URL=https://api\.deepseek\.com'; then
    backend=deepseek
fi

if [ -n "$backend" ]; then
    tmux set-option -p -t "$pane" @claude_backend "$backend" 2>/dev/null
else
    tmux set-option -pu -t "$pane" @claude_backend 2>/dev/null
fi
exit 0
