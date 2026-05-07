#!/usr/bin/env bash
set -euo pipefail

sock="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/im-gen.sock"

if [ "$#" -eq 0 ]; then
  echo "usage: imagine <prompt>" >&2
  exit 2
fi
prompt="$*"

if [ ! -S "$sock" ]; then
  echo "im-gen socket not found at $sock" >&2
  echo "  systemctl --user status im-gen-bot" >&2
  exit 1
fi

resp=$(printf '%s\n' "$prompt" | socat - "UNIX-CONNECT:$sock")

case "$resp" in
  "OK "*)
    path="${resp#OK }"
    echo "$path"
    if [ -t 1 ] || [ -n "${IMAGINE_OPEN:-}" ]; then
      if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$path" >/dev/null 2>&1 &
      fi
    fi
    ;;
  "BUSY "*)
    echo "GPU busy: ${resp#BUSY }" >&2
    exit 3
    ;;
  "ERR "*)
    echo "im-gen error: ${resp#ERR }" >&2
    exit 1
    ;;
  *)
    echo "unexpected response: $resp" >&2
    exit 1
    ;;
esac
