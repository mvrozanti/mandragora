#!/usr/bin/env bash
set -euo pipefail

password_file="${XDG_STATE_HOME:-$HOME/.local/state}/opencode/server-password"
if [ ! -s "$password_file" ]; then
  echo "oc: no server password at $password_file; is opencode-serve running? (systemctl --user status opencode-serve)" >&2
  exit 1
fi

exec opencode attach "http://127.0.0.1:${OPENCODE_PORT:-4096}" --dir "$PWD" -p "$(cat "$password_file")" "$@"
