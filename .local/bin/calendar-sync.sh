#!/usr/bin/env bash
set -euo pipefail

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/vdirsyncer"
ACCOUNTS=(google)

failed=0
synced=0
for account in "${ACCOUNTS[@]}"; do
  if [ ! -s "$STATE/$account.token" ]; then
    echo "calendar-sync: $account is not signed in, run: calendar-login $account"
    continue
  fi
  if vdirsyncer sync "$account"; then
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
