#!/usr/bin/env bash
stack=/tmp/scratchpad-stack
[ -s "$stack" ] || exit 0

current=$(hyprctl activeworkspace -j | jq -r '.id')

while [ -s "$stack" ]; do
  addr=$(tail -n1 "$stack")
  sed -i '$d' "$stack"
  if hyprctl clients -j | jq -e --arg a "$addr" '.[] | select(.address==$a and .workspace.name=="special:scratchpad")' >/dev/null; then
    hyprctl dispatch movetoworkspace "$current,address:$addr"
    exit 0
  fi
done
