#!/usr/bin/env bash
set -euo pipefail

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/vdirsyncer"
DAVMAIL_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/davmail"
DAVMAIL_PORT=1080
ACCOUNTS=(google hotmail)

signed_in() {
  case "$1" in
    google) [ -s "$STATE/google.token" ] ;;
    hotmail) [ -s "$DAVMAIL_STATE/tokens.properties" ] ;;
    *) return 1 ;;
  esac
}

bridge_up() {
  local attempt
  for attempt in $(seq 1 30); do
    if (exec 3<>"/dev/tcp/127.0.0.1/$DAVMAIL_PORT") 2>/dev/null; then
      return 0
    fi
    sleep 1
  done
  echo "calendar-sync: davmail did not answer on port $DAVMAIL_PORT after $attempt tries" >&2
  return 1
}

sync_account() {
  if [ "$1" = hotmail ]; then
    bridge_up || return 1
  fi
  vdirsyncer sync "$1"
}

failed=0
synced=0
for account in "${ACCOUNTS[@]}"; do
  if ! signed_in "$account"; then
    echo "calendar-sync: $account is not signed in, run: calendar-login $account"
    continue
  fi
  if sync_account "$account"; then
    synced=$((synced + 1))
    vdirsyncer metasync "$account" || true
  else
    failed=$((failed + 1))
    echo "calendar-sync: $account failed" >&2
  fi
done

if [ "$failed" -eq 0 ] && [ "$synced" -gt 0 ]; then
  date +%s > "$STATE/last-sync"
fi

[ "$failed" -eq 0 ]
