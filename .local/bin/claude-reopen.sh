#!/usr/bin/env bash
set -euo pipefail

sid="${1:?session id}"
cwd="${2:-$HOME}"

[ -d "$cwd" ] || {
    echo "claude-reopen: $cwd is gone, opening in $HOME" >&2
    cwd="$HOME"
}

cd "$cwd"
exec claude --resume "$sid"
