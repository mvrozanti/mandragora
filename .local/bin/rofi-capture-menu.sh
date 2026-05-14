#!/usr/bin/env bash
set -euo pipefail

if pgrep -x rofi >/dev/null 2>&1; then
  pkill -x rofi 2>/dev/null || true
  exit 0
fi

if [[ "$(screencap is-recording 2>/dev/null || echo no)" == yes ]]; then
  exec screencap stop
fi

has_mic=no
[[ "$(screencap has-mic 2>/dev/null || echo no)" == yes ]] && has_mic=yes

declare -a entries=()
entries+=("󰒉  Screenshot — Region|shot-region")
entries+=("󰖯  Screenshot — Window|shot-window")
entries+=("󰍹  Screenshot — Full|shot-full")
entries+=("󰕧  Video silent — Region|vid-none-region")
entries+=("󰕧  Video silent — Window|vid-none-window")
entries+=("󰕧  Video silent — Full|vid-none-full")
if [[ "$has_mic" == yes ]]; then
  entries+=("󰍬  Video mic — Region|vid-mic-region")
  entries+=("󰍬  Video mic — Window|vid-mic-window")
  entries+=("󰍬  Video mic — Full|vid-mic-full")
fi
entries+=("󰓃  Video system — Region|vid-sys-region")
entries+=("󰓃  Video system — Window|vid-sys-window")
entries+=("󰓃  Video system — Full|vid-sys-full")

menu=$(printf '%s\n' "${entries[@]%|*}")

prompt='Capture'
[[ "$has_mic" == no ]] && prompt='Capture (no mic)'

choice=$(printf '%s' "$menu" \
  | rofi -dmenu \
      -theme "$HOME/.config/rofi/themes/menu.rasi" \
      -p "$prompt" \
      -no-fixed-num-lines \
      -no-custom \
      -i \
      -format 's') || exit 0

[[ -z "$choice" ]] && exit 0

action=
for entry in "${entries[@]}"; do
  label=${entry%|*}
  if [[ "$label" == "$choice" ]]; then
    action=${entry##*|}
    break
  fi
done

[[ -z "$action" ]] && exit 0

exec screencap "$action"
