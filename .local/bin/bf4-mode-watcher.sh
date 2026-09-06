#!/usr/bin/env bash
set -euo pipefail

MATCH_RE='[Bb]attlefield|[Bb][Ff]4'

if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
  echo "HYPRLAND_INSTANCE_SIGNATURE not set" >&2
  exit 1
fi

runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
sock2="$runtime_dir/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

is_bf4() {
  local json class title
  json="$(hyprctl activewindow -j 2>/dev/null || true)"
  [ -n "$json" ] || return 1
  class="$(printf '%s' "$json" | jq -r '.class // empty' 2>/dev/null)"
  title="$(printf '%s' "$json" | jq -r '.title // empty' 2>/dev/null)"
  [[ "${class} ${title}" =~ ${MATCH_RE} ]]
}

disable_drag() {
  hyprctl keyword unbind 'ALT,mouse:272' >/dev/null 2>&1 || true
  hyprctl keyword unbind 'ALT,mouse:273' >/dev/null 2>&1 || true
}

enable_drag() {
  hyprctl keyword unbind 'ALT,mouse:272' >/dev/null 2>&1 || true
  hyprctl keyword unbind 'ALT,mouse:273' >/dev/null 2>&1 || true
  hyprctl keyword bindm 'ALT,mouse:272,movewindow' >/dev/null 2>&1 || true
  hyprctl keyword bindm 'ALT,mouse:273,resizewindow' >/dev/null 2>&1 || true
}

apply_state() {
  if is_bf4; then
    disable_drag
  else
    enable_drag
    hyprctl keyword input:sensitivity 0 >/dev/null 2>&1 || true
  fi
}

apply_state

exec socat -u "UNIX-CONNECT:$sock2" - | while IFS= read -r line; do
  case "$line" in
    activewindow\>\>*|activewindowv2\>\>*|configreloaded\>\>*) apply_state ;;
  esac
done
