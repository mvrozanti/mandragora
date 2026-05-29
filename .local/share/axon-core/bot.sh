#!/usr/bin/env bash
set -euo pipefail

if ! command -v axon >/dev/null 2>&1; then
    if [ -x /home/m/Projects/axon/build/axon ]; then
        export PATH="/home/m/Projects/axon/build:$PATH"
    elif [ -x "$HOME/.local/bin/axon" ]; then
        export PATH="$HOME/.local/bin:$PATH"
    else
        echo "axon binary not found in PATH, ~/.local/bin, or build/" >&2
        exit 127
    fi
fi

HOST="${AXON_BIND_HOST:-100.115.80.79}"
PORT="${AXON_BIND_PORT:-7070}"
WEB="${AXON_WEB_ROOT:-/home/m/Projects/axon/web/dist}"

exec axon serve --http --all --host="$HOST" --port="$PORT" --web-root="$WEB"
