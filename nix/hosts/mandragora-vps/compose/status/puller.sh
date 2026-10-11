#!/bin/sh
set -u

src="${SOURCE:-http://host.docker.internal:6684}"
every="${INTERVAL:-60}"
dir=/data
ok_at=null
fail_at=null
error=null

fetch() {
  tmp="$dir/.$1.tmp"
  wget -q -T 5 -O "$tmp" "$2" &&
    [ -s "$tmp" ] &&
    [ "$(head -c 1 "$tmp")" = "{" ] &&
    mv "$tmp" "$dir/$1"
}

while :; do
  now=$(date +%s)
  if fetch status.json "$src/api/status-snapshot"; then
    ok_at=$now
    error=null
  else
    fail_at=$now
    error='"desktop snapshot unreachable"'
  fi
  fetch theme.json "$src/api/theme?colors=1" || true
  printf '{"ok_at":%s,"fail_at":%s,"error":%s}\n' "$ok_at" "$fail_at" "$error" >"$dir/.pull.json.tmp" &&
    mv "$dir/.pull.json.tmp" "$dir/pull.json"
  rm -f "$dir/.status.json.tmp" "$dir/.theme.json.tmp"
  sleep "$every"
done
