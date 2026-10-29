#!/usr/bin/env bash
udevadm monitor --udev --subsystem-match=usb --property |
  while read -r line; do
    [ "$line" = "ACTION=add" ] || continue
    sig=$(hypr-live-instance) || continue
    export HYPRLAND_INSTANCE_SIGNATURE="$sig"
    hyprctl keyword input:repeat_rate 50
    hyprctl keyword input:repeat_delay 300
    hyprctl keyword input:kb_layout us
    hyprctl keyword input:kb_variant intl
  done
