#!/usr/bin/env bash
set -uo pipefail

msg="$*"
[ -n "$msg" ] || exit 0

inbox="${MANDRAGORA_INBOX_URL:-http://127.0.0.1:6688/api/inbox}"
source="${MANDRAGORA_NOTIFY_SOURCE:-desktop}"
level="${MANDRAGORA_NOTIFY_LEVEL:-}"
if [ -z "$level" ]; then
  if [ "${MANDRAGORA_NOTIFY_DESKTOP:-0}" = 1 ]; then level=alert; else level=info; fi
fi

payload=$(jq -cn \
  --arg text "$msg" \
  --arg source "$source" \
  --arg title "${MANDRAGORA_NOTIFY_TITLE:-$source}" \
  --arg level "$level" \
  --arg open "${MANDRAGORA_NOTIFY_OPEN:-}" \
  '{text: $text, source: $source, title: $title, level: $level} + (if $open == "" then {} else {open: $open} end)')

sent=0
if curl -fsS -m 10 -H 'Content-Type: application/json' --data-binary "$payload" "$inbox" >/dev/null 2>&1; then
  sent=1
fi

desktop() {
  local title="$1" headline="${msg%%$'\n'*}" bus owner shown=1
  for bus in /run/user/*/bus; do
    [ -S "$bus" ] || continue
    owner="$(stat -c %u "$bus")"
    if [ "$EUID" -eq "$owner" ]; then
      DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" \
        timeout 10 notify-send -u critical "$title" "$headline" 2>/dev/null && shown=0
    elif [ "$EUID" -eq 0 ]; then
      timeout 10 setpriv --reuid="$owner" --regid="$(stat -c %g "$bus")" --clear-groups \
        env DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" \
        notify-send -u critical "$title" "$headline" 2>/dev/null && shown=0
    fi
  done
  return "$shown"
}

if [ "$sent" -eq 1 ]; then
  if [ "${MANDRAGORA_NOTIFY_DESKTOP:-0}" = 1 ]; then
    desktop mandragora || true
  fi
  exit 0
fi

echo "mandragora-notify: the phone inbox at $inbox refused the message or was unreachable" >&2
desktop "mandragora (phone inbox unreachable)" && exit 0
echo "mandragora-notify: no desktop session took the message either" >&2
exit 1
