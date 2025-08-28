#!/usr/bin/env bash
ADAPTER="8C:88:4B:06:2B:14"
DEVICE="04:57:91:D1:38:20"

INFO=$(printf 'select %s\ninfo %s\n' "$ADAPTER" "$DEVICE" | bluetoothctl 2>/dev/null)
CONNECTED=$(printf '%s' "$INFO" | grep -q "Connected: yes" && printf 1 || printf 0)
BAT=$(printf '%s' "$INFO" | grep "Battery Percentage" | grep -oP '\(\K[0-9]+')

if [ "$CONNECTED" -eq 1 ]; then
  ICON="%{F#2196f3}%{F-}"
  CMD="bluetoothctl disconnect $DEVICE"
else
  ICON=""
  CMD="bluetoothctl connect $DEVICE"
fi

if [ -n "$BAT" ]; then
  TEXT="$ICON $BAT%"
else
  TEXT="$ICON ?%"
fi

CMD_B64=$(printf '%s' "$CMD" | base64 -w0)
ACTION="sh -c \"echo -n '$CMD_B64' | base64 -d | bash\""
printf "%%{A1:%s:}%s%%{A}\n" "$ACTION" "$TEXT"

