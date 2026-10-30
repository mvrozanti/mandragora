#!/usr/bin/env bash
set -u

MAC="04:57:91:D1:38:20"
MAC_U="${MAC//:/_}"
DEV="/org/bluez/hci0/dev_${MAC_U}"
INTERVAL="${BT_AUTOCONNECT_INTERVAL:-10}"
MAX_BACKOFF="${BT_AUTOCONNECT_MAX_BACKOFF:-300}"
SINK_GRACE="${BT_SINK_GRACE:-20}"

adapter_powered() {
  [ "$(busctl get-property org.bluez /org/bluez/hci0 org.bluez.Adapter1 Powered 2>/dev/null)" = "b true" ]
}

connected() {
  [ "$(busctl get-property org.bluez "$DEV" org.bluez.Device1 Connected 2>/dev/null)" = "b true" ]
}

other_link_up() {
  for link in /sys/class/bluetooth/hci0:*; do
    [ -e "$link" ] && return 0
  done
  return 1
}

has_sink() {
  pw-cli ls Node 2>/dev/null | grep -q "bluez_output.${MAC_U}"
}

no_sink_since=0
backoff="$INTERVAL"

while true; do
  wait="$INTERVAL"
  if adapter_powered; then
    if ! connected; then
      no_sink_since=0
      if ! other_link_up; then
        busctl call org.bluez "$DEV" org.bluez.Device1 Connect >/dev/null 2>&1 || true
        if connected; then
          backoff="$INTERVAL"
        else
          wait="$backoff"
          backoff=$((backoff * 2))
          [ "$backoff" -gt "$MAX_BACKOFF" ] && backoff="$MAX_BACKOFF"
        fi
      fi
    elif has_sink; then
      no_sink_since=0
      backoff="$INTERVAL"
    else
      now=$(date +%s)
      if [ "$no_sink_since" -eq 0 ]; then
        no_sink_since="$now"
      elif [ $((now - no_sink_since)) -ge "$SINK_GRACE" ]; then
        busctl call org.bluez "$DEV" org.bluez.Device1 Disconnect >/dev/null 2>&1 || true
        sleep 3
        busctl call org.bluez "$DEV" org.bluez.Device1 Connect >/dev/null 2>&1 || true
        no_sink_since=0
      fi
    fi
  fi
  sleep "$wait"
done
