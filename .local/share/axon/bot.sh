#!/usr/bin/env bash
set -euo pipefail

if [ -x /home/m/Projects/axon/build/axon ]; then
    export PATH="/home/m/Projects/axon/build:$PATH"
elif [ -x "$HOME/.local/bin/axon" ]; then
    export PATH="$HOME/.local/bin:$PATH"
elif ! command -v axon >/dev/null 2>&1; then
    echo "axon binary not found in build/, ~/.local/bin, or PATH" >&2
    exit 127
fi

HOST="${AXON_BIND_HOST:-127.0.0.1}"
PORT="${AXON_BIND_PORT:-7070}"

exec axon serve --http --all --host="$HOST" --port="$PORT"
