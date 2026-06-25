#!/usr/bin/env bash
set -u

MAC="04:57:91:D1:38:20"
INTERVAL="${BT_AUTOCONNECT_INTERVAL:-10}"

while true; do
  if bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then
    if ! bluetoothctl info "$MAC" 2>/dev/null | grep -q "Connected: yes"; then
      bluetoothctl connect "$MAC" >/dev/null 2>&1 || true
    fi
  fi
  sleep "$INTERVAL"
done
