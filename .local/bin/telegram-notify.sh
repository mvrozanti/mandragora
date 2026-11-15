#!/usr/bin/env bash
set -uo pipefail

msg="$*"
[ -n "$msg" ] || exit 0

target="${TELEGRAM_CHAT_ID:-${ALLOWED_USER_ID:-}}"
sent=0
why="no bot token or chat id in the environment"
if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "$target" ]; then
  why="telegram refused the message or was unreachable"
  IFS=', ' read -ra chats <<< "$target"
  for chat in "${chats[@]}"; do
    [ -n "$chat" ] || continue
    if curl -fsS -m 20 -X POST \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${chat}" \
        --data-urlencode "text=${msg}" \
        -d disable_web_page_preview=true >/dev/null 2>&1; then
      sent=1
    fi
  done
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

echo "telegram-notify: $why" >&2
desktop "mandragora (telegram page failed)" && exit 0
echo "telegram-notify: no desktop session took the message either" >&2
exit 1
