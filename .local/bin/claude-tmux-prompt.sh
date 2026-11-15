#!/usr/bin/env bash
set -euo pipefail

program="${1:?usage: claude-tmux-prompt <program> [prompt]}"
shift
prompt="${*:-}"

windows="$(hyprctl clients -j)"
active_window="$(hyprctl activewindow -j | jq -r '.address // empty')"

terminal_window_of() {
    local pid="$1" address
    while [ "${pid:-1}" -gt 1 ]; do
        address="$(jq -r --argjson pid "$pid" 'first(.[] | select(.pid == $pid) | .address) // empty' <<<"$windows")"
        if [ -n "$address" ]; then
            printf '%s\n' "$address"
            return 0
        fi
        pid="$(ps -o ppid= -p "$pid" | tr -d ' ')"
    done
    return 1
}

focus_window() {
    local address="$1"
    for _ in $(seq 40); do
        hyprctl dispatch focuswindow "address:$address" >/dev/null || true
        if [ "$(hyprctl activewindow -j | jq -r '.address // empty')" = "$address" ]; then
            return 0
        fi
        sleep 0.05
    done
    return 1
}

session=""
terminal_window=""
while read -r _ client_pid client_session; do
    client_window="$(terminal_window_of "$client_pid")" || continue
    if [ -z "$session" ] || [ "$client_window" = "$active_window" ]; then
        session="$client_session"
        terminal_window="$client_window"
    fi
    if [ "$client_window" = "$active_window" ]; then
        break
    fi
done < <(tmux list-clients -F '#{client_activity} #{client_pid} #{session_id}' 2>/dev/null | sort -rn || true)

if [ -z "$session" ]; then
    session="$(tmux list-sessions -F '#{session_last_attached} #{session_id}' 2>/dev/null | sort -rn | head -n1 | cut -d' ' -f2 || true)"
fi
if [ -n "$session" ]; then
    cwd="$(tmux display-message -p -t "${session}:" '#{pane_current_path}')"
else
    session="$(tmux new-session -d -P -F '#{session_id}' -c "$HOME")"
    cwd="$HOME"
fi

command=("$program")
if [ -n "$prompt" ]; then
    command+=("$prompt")
fi

tmux new-window -t "${session}:" -c "${cwd:-$HOME}" -- "${command[@]}"

if [ -n "$terminal_window" ]; then
    if ! focus_window "$terminal_window"; then
        echo "claude started, but its terminal could not be focused"
        exit 1
    fi
else
    hyprctl dispatch exec "kitty tmux attach-session -t '${session}'" >/dev/null
fi
