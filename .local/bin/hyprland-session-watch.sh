#!/usr/bin/env bash
set -euo pipefail
link=/run/current-system/sw/bin/Hyprland
[ -e "$link" ] || exit 0
runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
state="$runtime/hyprland-session-watch"
mkdir -p "$state"
installed=$(readlink -f "$link")
installed=${installed%/bin/*}
now=$(date +%s)

label() {
  local name=${1#/nix/store/}
  printf '%s (%s)' "${name#*-}" "${name:0:8}"
}

alert() {
  local key=$1 every=$2 title=$3 body=$4 last
  last=$(cat "$state/$key" 2>/dev/null || echo 0)
  [ $((now - last)) -ge "$every" ] || return 0
  notify-send -u critical "$title" "$body" || return 0
  echo "$now" > "$state/$key"
}

for lock in "$runtime"/hypr/*/hyprland.lock; do
  [ -e "$lock" ] || continue
  read -r pid < "$lock" || continue
  args=$(tr '\0' '\n' 2>/dev/null < "/proc/$pid/cmdline") || continue
  argv0=${args%%$'\n'*}
  case "$argv0" in
    /nix/store/*/bin/Hyprland) ;;
    *) continue ;;
  esac
  running=${argv0%/bin/*}
  if grep -qx -- --safe-mode <<< "$args"; then
    alert "safe-$pid" 1800 "Hyprland is in safe mode" \
      "It crashed and came back without your config. Press SUPER+M to log out; autologin brings you straight back with your config."
  fi
  if [ "$running" != "$installed" ]; then
    alert "stale-$pid-${installed:11:8}" 21600 "Hyprland update is not live" \
      "Running $(label "$running"), installed $(label "$installed"). Log out (SUPER+Delete) and autologin loads the new one."
  fi
done
