#!/usr/bin/env bash
set -uo pipefail

msg="$*"
[ -n "$msg" ] || exit 0

sent=0
if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
  IFS=', ' read -ra chats <<< "$TELEGRAM_CHAT_ID"
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

if [ "$sent" -eq 0 ] && command -v notify-send >/dev/null 2>&1; then
  notify-send "mandragora" "$msg" 2>/dev/null || true
fi
exit 0
