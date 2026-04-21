#!/usr/bin/env bash
# Event-driven volume module for waybar (pipewire-native).
# Streams one JSON line on startup, then one per pw-mon event.
# No polling, no pkill refresh.

emit() {
  local vol muted pct icon class
  vol=$(pamixer --get-volume 2>/dev/null || echo 0)
  muted=$(pamixer --get-mute 2>/dev/null || echo false)

  pct=$(( (vol + 2) / 5 * 5 ))
  (( pct > 100 )) && pct=100

  if [[ "$muted" == "true" ]]; then
    icon="󰝟"
    class="muted"
  else
    if (( vol == 0 )); then icon="󰝟"
    elif (( vol <= 30 )); then icon="󰕿"
    elif (( vol <= 70 )); then icon="󰖀"
    else icon="󰕾"
    fi
    class="v${pct}"
  fi

  printf '{"text": "%s %d%%", "class": "%s", "tooltip": "Volume: %d%%", "percentage": %d}\n' \
    "$icon" "$vol" "$class" "$vol" "$vol"
}

emit

# pw-mon streams pipewire events. We debounce to avoid bursts: coalesce any
# events arriving within 80ms into a single re-emit.
pw-mon 2>/dev/null | while IFS= read -r line; do
  case "$line" in
    *changed:*|*added:*|*removed:*) ;;
    *) continue ;;
  esac
  # drain anything queued in the next 80ms
  while IFS= read -r -t 0.08 _; do :; done
  emit
done
