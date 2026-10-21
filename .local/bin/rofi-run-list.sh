#!/usr/bin/env bash
cache="${XDG_CACHE_HOME:-$HOME/.cache}/rofi-run-list"

refresh() {
  local tmp="$cache.tmp.$$"
  mkdir -p "$(dirname "$cache")"
  POWERLEVEL9K_DISABLE_GITSTATUS=true \
    zsh -i -c 'print -rl -- ${(k)commands} ${(k)aliases} ${(k)functions}' </dev/null 2>/dev/null \
    | grep -v '^_\| ' | sort -u >"$tmp" && mv "$tmp" "$cache"
}

if [ "$1" = --refresh ]; then
  refresh
  exit
fi

[ -s "$cache" ] || refresh
cat "$cache"
setsid -f "$0" --refresh </dev/null >/dev/null 2>&1
