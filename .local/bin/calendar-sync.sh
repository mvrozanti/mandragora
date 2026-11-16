#!/usr/bin/env bash
set -euo pipefail

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/vdirsyncer"
DAVMAIL_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/davmail"
DAVMAIL_PORT=1080
HOTMAIL_URL="http://127.0.0.1:$DAVMAIL_PORT/users/mvrozanti@hotmail.com/calendar/"
HOTMAIL_LOCAL="${XDG_DATA_HOME:-$HOME/.local/share}/calendars/hotmail/calendar"
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

listing_whole() {
  local held listed
  held=$(find "$HOTMAIL_LOCAL" -maxdepth 1 -name '*.ics' 2>/dev/null | wc -l)
  [ "$held" -ge 20 ] || return 0
  listed=$(curl -s -m 180 -u "mvrozanti@hotmail.com:davmail" -X PROPFIND -H "Depth: 1" \
    -H "Content-Type: application/xml" \
    --data '<?xml version="1.0"?><propfind xmlns="DAV:"><prop><getetag/></prop></propfind>' \
    "$HOTMAIL_URL" | grep -o '<D:href>' | wc -l)
  listed=$((listed > 0 ? listed - 1 : 0))
  if [ $((listed * 2)) -lt "$held" ]; then
    echo "calendar-sync: davmail listed $listed events, the desktop holds $held; skipping hotmail this run"
    return 1
  fi
}

sync_account() {
  if [ "$1" = hotmail ]; then
    bridge_up || return 1
    listing_whole || return 2
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
  rc=0
  sync_account "$account" || rc=$?
  if [ "$rc" -eq 0 ]; then
    synced=$((synced + 1))
    vdirsyncer metasync "$account" || true
  elif [ "$rc" -ne 2 ]; then
    failed=$((failed + 1))
    echo "calendar-sync: $account failed" >&2
  fi
done

if [ "$failed" -eq 0 ] && [ "$synced" -gt 0 ]; then
  date +%s > "$STATE/last-sync"
fi

[ "$failed" -eq 0 ]
