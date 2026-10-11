#!/usr/bin/env bash
set -euo pipefail

if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
  echo "HYPRLAND_INSTANCE_SIGNATURE not set" >&2
  exit 1
fi

runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
sock2="$runtime_dir/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

covered_by_fullscreen() {
  hyprctl -j clients 2>/dev/null | jq -e --arg a "$1" '
    (map(select(.address == $a)) | first) as $new
    | $new != null
      and $new.floating
      and ($new.pinned | not)
      and $new.fullscreen == 0
      and any(.[]; .workspace.id == $new.workspace.id and .fullscreen == 2)
  ' >/dev/null 2>&1
}

socat -u "UNIX-CONNECT:$sock2" - | while IFS= read -r line; do
  case "$line" in
    openwindow\>\>*)
      payload="${line#openwindow>>}"
      address="0x${payload%%,*}"
      if covered_by_fullscreen "$address"; then
        hyprctl dispatch alterzorder "bottom,address:$address" >/dev/null 2>&1 || true
      fi
      ;;
  esac
done
