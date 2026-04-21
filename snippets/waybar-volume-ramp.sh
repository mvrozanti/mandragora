#!/usr/bin/env bash
vol=$(pamixer --get-volume 2>/dev/null || echo 0)
muted=$(pamixer --get-mute 2>/dev/null || echo false)
filled=$((vol * 15 / 100))
empty=$((15 - filled))
bar=$(printf '%0.s─' $(seq 1 $filled 2>/dev/null) ; printf '%0.s─' $(seq 1 $empty 2>/dev/null))
bar="${bar:0:$filled}|${bar:$filled}"
if [[ "$muted" == "true" ]]; then
  printf '{"text": " %s", "class": "muted", "percentage": %d}\n' "$bar" "$vol"
else
  printf '{"text": " %s", "class": "vol-%d", "percentage": %d}\n' "$bar" "$((vol / 20))" "$vol"
fi
