#!/usr/bin/env bash
ADAPTER="8C:88:4B:06:2B:14"
DEVICE="04:57:91:D1:38:20"
SINK_BT="bluez_output.04_57_91_D1_38_20.1"
SINK_HDMI="alsa_output.pci-0000_01_00.1.hdmi-stereo"

INFO=$(printf 'select %s\ninfo %s\n' "$ADAPTER" "$DEVICE" | bluetoothctl 2>/dev/null)
CONNECTED=$(printf '%s' "$INFO" | grep -q "Connected: yes" && printf 1 || printf 0)
BAT=$(printf '%s' "$INFO" | grep "Battery Percentage" | grep -oP '\(\K[0-9]+')
CURRENT_SINK=$(pactl info | grep "Default Sink" | awk '{print $3}')

if [ "$CONNECTED" -eq 1 ]; then
    ICON="%{F#2196f3}%{F-}"
    if [ "$CURRENT_SINK" = "$SINK_BT" ]; then
        CMD="printf 'select %s\ndisconnect %s\n' \"$ADAPTER\" \"$DEVICE\" | bluetoothctl && pactl set-default-sink $SINK_HDMI"
    else
        # inline wait loop for the subshell
        CMD="for i in {1..10}; do pactl list short sinks | grep -q '$SINK_BT' && break; sleep 1; done; pactl set-default-sink $SINK_BT"
    fi
else
    ICON=""
    CMD="printf 'select %s\nconnect %s\n' \"$ADAPTER\" \"$DEVICE\" | bluetoothctl; for i in {1..10}; do pactl list short sinks | grep -q '$SINK_BT' && break; sleep 1; done; pactl set-default-sink $SINK_BT"
fi

if [ -n "$BAT" ]; then
    TEXT="$ICON $BAT%"
else
    TEXT="$ICON"
fi

CMD_B64=$(printf '%s' "$CMD" | base64 -w0)
ACTION="sh -c \"echo -n '$CMD_B64' | base64 -d | bash\""
printf "%%{A1:%s:}%s%%{A}\n" "$ACTION" "$TEXT"

