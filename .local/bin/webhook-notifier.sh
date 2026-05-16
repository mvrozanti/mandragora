#!/usr/bin/env bash
set -uo pipefail

URL="${WEBHOOK_NOTIFIER_URL:-https://webhook.mvr.ac/internal/events}"
UI_BASE="${WEBHOOK_NOTIFIER_UI:-https://webhook.mvr.ac}"
APP="webhook.mvr.ac"
ICON="${WEBHOOK_NOTIFIER_ICON:-network-receive}"

emit() {
  local json="$1"
  local hook_name method content_type size ip event_id body action
  hook_name=$(jq -r '.hook_name // "?"' <<<"$json")
  method=$(jq -r '.method // "?"' <<<"$json")
  content_type=$(jq -r '.content_type // "—"' <<<"$json")
  size=$(jq -r '.body_size // 0' <<<"$json")
  ip=$(jq -r '.remote_ip // ""' <<<"$json")
  event_id=$(jq -r '.id // 0' <<<"$json")
  body="${method} · ${content_type} · ${size}B"
  [ -n "$ip" ] && body+=" · ${ip}"
  (
    action=$(notify-send --wait -a "$APP" -i "$ICON" \
      --action="open=open" \
      "webhook: ${hook_name}" "$body" 2>/dev/null) || true
    if [ "$action" = "open" ]; then
      xdg-open "${UI_BASE}/" >/dev/null 2>&1 &
    fi
  ) &
}

stream_once() {
  curl -sN --connect-timeout 10 --max-time 0 \
    -H "Accept: text/event-stream" \
    --no-buffer "$URL" 2>/dev/null \
  | while IFS= read -r line; do
      case "$line" in
        "data: "*) emit "${line#data: }" ;;
        *) : ;;
      esac
    done
}

backoff=2
while true; do
  start=$(date +%s)
  stream_once
  now=$(date +%s)
  if (( now - start > 30 )); then
    backoff=2
  else
    backoff=$(( backoff < 60 ? backoff * 2 : 60 ))
  fi
  sleep "$backoff"
done
