#!/usr/bin/env bash
set -euo pipefail

if ! command -v axon >/dev/null 2>&1; then
    echo "axon binary not found in PATH" >&2
    exit 127
fi

HOST="${AXON_BIND_HOST:-127.0.0.1}"
PORT="${AXON_BIND_PORT:-7070}"

exec axon serve --http --all --host="$HOST" --port="$PORT"
