#!/usr/bin/env bash
set -euo pipefail

orig_arg="${1:-}"

resolve_dir() {
    local arg="$1"
    case "$arg" in
        '~')   arg="$HOME" ;;
        '~/'*) arg="$HOME/${arg#\~/}" ;;
    esac
    if [[ "$arg" = /* ]]; then
        [ -d "$arg" ] && { printf '%s\n' "$arg"; return 0; }
        return 1
    fi
    for base in "$HOME" "$HOME/Projects"; do
        if [ -d "$base/$arg" ]; then
            printf '%s\n' "$base/$arg"
            return 0
        fi
    done
    local matches
    mapfile -d '' -t matches < <(
        find "$HOME" "$HOME/Projects" \
            -mindepth 1 -maxdepth 1 -type d -iname "$arg" -print0 2>/dev/null
    )
    if [ "${#matches[@]}" -eq 1 ]; then
        printf '%s\n' "${matches[0]}"
        return 0
    fi
    return 1
}

session="$(tmux list-sessions -F '#{session_name}' 2>/dev/null | head -n1 || true)"
if [ -z "$session" ]; then
    echo "spawn-claude-tmux: no tmux server / session running" >&2
    exit 1
fi

window_name="claude-$(date +%H%M%S)"

if [ -z "$orig_arg" ]; then
    cwd="$HOME"
    shell_cmd="exec claude"
    note="cwd: ${cwd}"
elif resolved="$(resolve_dir "$orig_arg")"; then
    cwd="$resolved"
    shell_cmd="exec claude"
    note="cwd: ${cwd}"
else
    cwd="$HOME"
    prompt="The wrapper was asked to start this session in '${orig_arg}' but found no matching directory under ~ or ~/Projects. Search both with fd/find, list candidates, and tell me the right path so I can relaunch with it (you cannot change your own cwd)."
    shell_cmd="exec claude $(printf '%q' "$prompt")"
    note="cwd: ${cwd} (asked='${orig_arg}' unresolved — claude will help locate)"
fi

tmux new-window -t "${session}:" -n "$window_name" -c "$cwd" "$shell_cmd"

echo "spawned '${window_name}' in tmux session '${session}' (${note}). attach via the Claude app."
