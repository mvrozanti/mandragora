#!/usr/bin/env bash
set -euo pipefail
state="${XDG_RUNTIME_DIR:-/tmp}/link-speed-watch"
mkdir -p "$state"
for dev in /sys/class/net/*; do
  [ -e "$dev/device" ] || continue
  [ -d "$dev/wireless" ] && continue
  read -r carrier < "$dev/carrier" 2>/dev/null || continue
  [ "$carrier" = 1 ] || continue
  read -r speed < "$dev/speed" 2>/dev/null || continue
  [ "$speed" -gt 0 ] && [ "$speed" -lt 1000 ] || continue
  read -r changes < "$dev/carrier_changes"
  name=${dev##*/}
  seen="$state/$name"
  [ "$(cat "$seen" 2>/dev/null)" = "$changes" ] && continue
  notify-send -u critical "Ethernet below gigabit" "$name linked at $speed Mb/s: check the cable or the router port"
  echo "$changes" > "$seen"
done
