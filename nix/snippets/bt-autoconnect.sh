#!/usr/bin/env bash
set -u

MAC="04:57:91:D1:38:20"
MAC_U="${MAC//:/_}"
DEV="/org/bluez/hci0/dev_${MAC_U}"
INTERVAL="${BT_AUTOCONNECT_INTERVAL:-10}"
SINK_GRACE="${BT_SINK_GRACE:-20}"

adapter_powered() {
  [ "$(busctl get-property org.bluez /org/bluez/hci0 org.bluez.Adapter1 Powered 2>/dev/null)" = "b true" ]
}

connected() {
  [ "$(busctl get-property org.bluez "$DEV" org.bluez.Device1 Connected 2>/dev/null)" = "b true" ]
}

has_sink() {
  pw-cli ls Node 2>/dev/null | grep -q "bluez_output.${MAC_U}"
}

no_sink_since=0

while true; do
  if adapter_powered; then
    if ! connected; then
      busctl call org.bluez "$DEV" org.bluez.Device1 Connect >/dev/null 2>&1 || true
      no_sink_since=0
    elif has_sink; then
      no_sink_since=0
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
  sleep "$INTERVAL"
done
