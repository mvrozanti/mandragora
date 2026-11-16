#!/usr/bin/env bash
set -euo pipefail

port="${OPENCODE_PORT:-4096}"
password_file="${XDG_STATE_HOME:-$HOME/.local/state}/opencode/server-password"

if ! systemctl --user is-active --quiet opencode-serve; then
  systemctl --user start opencode-serve
fi
deadline=$((SECONDS + 30))
until [ -s "$password_file" ] && (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; do
  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "oc: opencode-serve did not come up on :$port within 30s (systemctl --user status opencode-serve)" >&2
    exit 1
  fi
  sleep 0.2
done

exec opencode attach "http://127.0.0.1:$port" --dir "$PWD" -p "$(cat "$password_file")" "$@"
