#!/usr/bin/env bash
# Re-apply the last pywal wallpaper on login, once awww-daemon is up.
set -u

for _ in $(seq 1 20); do
    awww query >/dev/null 2>&1 && break
    sleep 0.25
done

last="$HOME/.cache/wal/wal"
if [[ -s "$last" ]]; then
    wp="$(head -1 "$last")"
    [[ -e "$wp" ]] && exec setbg "$wp"
fi
exec setbg
