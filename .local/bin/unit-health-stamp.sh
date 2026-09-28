#!/usr/bin/env bash
set -u

unit="${1:-}"
[ -n "$unit" ] || exit 0
[ "${SERVICE_RESULT:-}" = success ] || exit 0

if [ "$EUID" -eq 0 ]; then
  dir="@systemDir@"
  scope=--system
else
  dir="${XDG_STATE_HOME:-$HOME/.local/state}/unit-health"
  scope=--user
fi

mkdir -p "$dir" 2>/dev/null || exit 0
: > "$dir/$unit.ok" 2>/dev/null || exit 0

if [ -e "$dir/$unit.failing" ]; then
  mv -f "$dir/$unit.failing" "$dir/$unit.recovered" 2>/dev/null || exit 0
  systemctl "$scope" start --no-block "unit-health-recovered@$unit.service" 2>/dev/null || true
fi
exit 0
