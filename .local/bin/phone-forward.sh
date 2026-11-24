#!/usr/bin/env bash
set -euo pipefail

file="${PHONE_FORWARD_FILE:?}"

state() {
  if [[ "$(jq -r '.on' "$file" 2>/dev/null)" == false ]]; then
    echo off
  else
    echo on
  fi
}

switch_to() {
  mkdir -p "${file%/*}"
  local tmp="$file.$$"
  jq -n --argjson on "$1" '{on: $on}' >"$tmp"
  mv -f "$tmp" "$file"
  pkill -RTMIN+16 -x waybar || true
  state
}

case "${1:-state}" in
  state) state ;;
  on) switch_to true ;;
  off) switch_to false ;;
  toggle)
    if [[ "$(state)" == on ]]; then
      switch_to false
    else
      switch_to true
    fi
    ;;
  *)
    echo "usage: phone-forward [state|on|off|toggle]" >&2
    exit 2
    ;;
esac
