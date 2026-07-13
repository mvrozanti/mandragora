#!/usr/bin/env bash
set -euo pipefail

UNIT="${1:-unknown-unit}"
MARKER_DIR="${MANDRAGORA_BACKUP_MARKER_DIR:-/persistent/backup}"
NOTIFY="${MANDRAGORA_NOTIFY_BIN:-}"

stamp=$(date -Is)
if mkdir -p "$MARKER_DIR" 2>/dev/null; then
  printf '%s failed at %s\n' "$UNIT" "$stamp" >> "$MARKER_DIR/last-failure" || true
fi

msg="mandragora backup alert: $UNIT failed at $stamp"
if [ -n "$NOTIFY" ]; then
  "$NOTIFY" "$msg" || true
elif command -v notify-send >/dev/null 2>&1; then
  notify-send "mandragora backup" "$msg" || true
fi

echo "$msg" >&2
