#!/usr/bin/env bash
set -euo pipefail

export DISPLAY="${DISPLAY:-:0}"

monitors="$(hyprctl monitors -j 2>/dev/null || true)"
[[ -z "$monitors" ]] && exit 0

workarea="$(printf '%s\n' "$monitors" | jq -r '
  ([.[] | select(.focused == true)][0] // .[0]) as $m
  | select($m != null)
  | [($m.x + $m.reserved[0]),
     ($m.y + $m.reserved[1]),
     ($m.width  - $m.reserved[0] - $m.reserved[2]),
     ($m.height - $m.reserved[1] - $m.reserved[3])]
  | join(",")
')"

[[ -z "$workarea" || "$workarea" == "null" ]] && exit 0

xprop -root -f _NET_WORKAREA 32c -set _NET_WORKAREA "$workarea"
