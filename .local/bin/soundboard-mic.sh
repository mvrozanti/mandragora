#!/usr/bin/env bash
set -euo pipefail

REAL="alsa_input.pci-0000_10_00.6.analog-stereo"
VIRT="VirtualMic"

cur=$(pactl get-default-source)

case "${1:-toggle}" in
  on)
    pactl set-default-source "$VIRT"
    notify-send "Mic" "VirtualMic active — game hears mic + soundboard"
    ;;
  off)
    pactl set-default-source "$REAL"
    notify-send "Mic" "Real mic active"
    ;;
  toggle)
    if [[ "$cur" == "$VIRT" ]]; then
      pactl set-default-source "$REAL"
      notify-send "Mic" "Real mic active"
    else
      pactl set-default-source "$VIRT"
      notify-send "Mic" "VirtualMic active — game hears mic + soundboard"
    fi
    ;;
esac
