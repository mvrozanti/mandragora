#!/usr/bin/env bash
set -euo pipefail

if pgrep -x rofi >/dev/null 2>&1; then
  pkill -x rofi 2>/dev/null || true
  exit 0
fi

choice=$(printf '%s\n' \
  '󰌾  Lock' \
  '󰤄  Suspend' \
  '󰜗  Hibernate' \
  '󰜉  Reboot' \
  '󰐥  Power off' \
  | rofi -dmenu \
      -theme "$HOME/.config/rofi/themes/menu.rasi" \
      -no-fixed-num-lines \
      -no-custom \
      -format 's') || exit 0

[[ -z "$choice" ]] && exit 0

case "$choice" in
  *Lock*)        exec hyprlock ;;
  *Suspend*)     exec systemctl suspend ;;
  *Hibernate*)   exec systemctl hibernate ;;
  *Reboot*)      exec systemctl reboot ;;
  *Power\ off*)  exec systemctl poweroff ;;
esac
