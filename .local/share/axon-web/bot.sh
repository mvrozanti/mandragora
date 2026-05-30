#!/usr/bin/env bash
set -euo pipefail

REPO="${AXON_WEB_REPO:-/home/m/Projects/axon-web}"

if ! command -v node >/dev/null 2>&1; then
    echo "node binary not found in PATH" >&2
    exit 127
fi

if [ ! -s "$REPO/server.mjs" ]; then
    echo "server.mjs missing at $REPO" >&2
    exit 1
fi

export AXON_WEB_HOST="${AXON_WEB_HOST:-100.115.80.79}"
export AXON_WEB_PORT="${AXON_WEB_PORT:-8081}"
export AXON_UPSTREAM="${AXON_UPSTREAM:-http://127.0.0.1:7070}"
export AXON_WEB_ROOT="${AXON_WEB_ROOT:-$REPO/dist}"

cd "$REPO"
exec node server.mjs
