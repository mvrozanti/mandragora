#!/usr/bin/env bash
set -u

for _ in $(seq 1 40); do
    awww query >/dev/null 2>&1 && break
    sleep 0.25
done

awww query >/dev/null 2>&1 || exit 0

last="$HOME/.cache/matugen/last-wallpaper"
[[ -s "$last" ]] || exit 0

wp="$(head -1 "$last")"
[[ -e "$wp" ]] || exit 0

exec awww img "$wp"
