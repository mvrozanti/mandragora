#!/usr/bin/env bash
workspace="${STEAM_GAME_WORKSPACE:-9}"

HYPRLAND_INSTANCE_SIGNATURE=$(hypr-live-instance) || {
  echo "no live Hyprland instance to watch" >&2
  exit 1
}
export HYPRLAND_INSTANCE_SIGNATURE
sock="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

launched_by_steam() {
  local pid=$1
  while [ "$pid" -gt 1 ] 2>/dev/null; do
    grep -qaz '^SteamGameId=[1-9]' "/proc/$pid/environ" 2>/dev/null && return 0
    [ "$(cat "/proc/$pid/comm" 2>/dev/null)" = reaper ] && return 0
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ') || return 1
  done
  return 1
}

socat -u "UNIX-CONNECT:$sock" - | while IFS= read -r line; do
  [[ $line == openwindow\>\>* ]] || continue
  addr="${line#openwindow>>}"
  addr="0x${addr%%,*}"
  info=$(hyprctl clients -j 2>/dev/null | jq -r --arg a "$addr" '.[] | select(.address == $a) | "\(.pid) \(.workspace.id)"') || continue
  [ -n "$info" ] || continue
  pid=${info% *}
  ws=${info#* }
  [ "$ws" = "$workspace" ] && continue
  launched_by_steam "$pid" || continue
  hyprctl dispatch movetoworkspace "$workspace,address:$addr" >/dev/null || true
done
