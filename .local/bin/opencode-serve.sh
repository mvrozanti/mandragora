#!/usr/bin/env bash
set -euo pipefail

state="${XDG_STATE_HOME:-$HOME/.local/state}/opencode"
password_file="$state/server-password"

if [ ! -s "$password_file" ]; then
  umask 077
  mkdir -p "$state"
  head -c 24 /dev/urandom | base64 | tr -d '/+=\n' > "$password_file.tmp"
  mv -f "$password_file.tmp" "$password_file"
fi

OPENCODE_SERVER_PASSWORD="$(cat "$password_file")"
export OPENCODE_SERVER_PASSWORD

exec opencode serve --hostname "${OPENCODE_HOST:-0.0.0.0}" --port "${OPENCODE_PORT:-4096}"
