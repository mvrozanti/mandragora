#!/usr/bin/env bash
DELAY=${DELAY:-3}
OUTPUT=${1:-/tmp/recorded.mp4}

read -r x y w h < <(slurp -f "%x %y %w %h")
[[ -z "$x" ]] && exit 1

echo "Recording in $DELAY seconds... (Ctrl+C to stop)"
for (( i=DELAY; i>0; i-- )); do echo "$i"; sleep 1; done

notify-send "Recording" "Started — Ctrl+C to stop"
wf-recorder -g "${x},${y} ${w}x${h}" -f "$OUTPUT"
notify-send "Recording" "Saved to $OUTPUT"
