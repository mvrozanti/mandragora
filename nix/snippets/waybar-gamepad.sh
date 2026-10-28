#!/usr/bin/env bash
shopt -s nullglob
ICON="󰊴"
CHARGING="󱐋"
LOW=20

model() {
  case "$1" in
    *:0000054C:000005C4 | *:0000054C:000009CC) echo "DualShock 4" ;;
    *:0000054C:00000CE6) echo "DualSense" ;;
    *:0000054C:00000DF2) echo "DualSense Edge" ;;
    *) echo "PlayStation controller" ;;
  esac
}

texts=()
tips=()
cls=""
for ps in /sys/class/power_supply/ps-controller-battery-* /sys/class/power_supply/sony_controller_battery_*; do
  [ -r "$ps/capacity" ] || continue
  cap=$(<"$ps/capacity")
  status=$(<"$ps/status")
  hid=$(sed -n 's/^HID_ID=//p' "$ps/device/uevent")
  case "${hid%%:*}" in
    0003) link="USB" ;;
    0005) link="Bluetooth" ;;
    *) link="unknown link" ;;
  esac
  text="$ICON $cap%"
  [ "$status" = "Charging" ] && text="$text $CHARGING"
  texts+=("$text")
  tips+=("$(model "$hid") · $link · $cap% ${status,,}")
  if [ "$status" = "Discharging" ] && [ "$cap" -le "$LOW" ]; then
    cls="low"
  fi
done

if [ ${#texts[@]} -eq 0 ]; then
  printf '{"text": ""}\n'
  exit 0
fi

tooltip=$(printf '%s\\n' "${tips[@]}")
printf '{"text": "%s", "class": "%s", "tooltip": "%s"}\n' "${texts[*]}" "$cls" "${tooltip%\\n}"
