#!/usr/bin/env bash
dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr"
best=""
best_epoch=0
for d in "$dir"/*/; do
  [ -S "$d/.socket.sock" ] || continue
  sig=$(basename "$d")
  epoch=${sig#*_}
  epoch=${epoch%%_*}
  [ "$epoch" -gt "$best_epoch" ] 2>/dev/null || continue
  HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl version >/dev/null 2>&1 || continue
  best="$sig"
  best_epoch="$epoch"
done
[ -n "$best" ] || exit 1
echo "$best"
