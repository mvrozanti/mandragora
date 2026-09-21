#!/usr/bin/env bash
set -uo pipefail

log="${XDG_STATE_HOME:-$HOME/.local/state}/calibre-reaper.log"
mkdir -p "$(dirname "$log")"
say() { printf '[%s] %s\n' "$(date +%FT%T%z)" "$*" >>"$log"; }

for pid in $(pgrep -f 'calibre-parallel.*--pipe-worker' 2>/dev/null); do
  ppid=$(awk '{print $4}' "/proc/$pid/stat" 2>/dev/null) || continue
  [ -n "$ppid" ] || continue
  pstate=$(awk '{print $3}' "/proc/$ppid/stat" 2>/dev/null)
  if [ "$ppid" = "1" ] || [ "$pstate" = "Z" ]; then
    say "reaping orphaned calibre pipe-worker pid=$pid ppid=$ppid pstate=$pstate"
    kill -TERM "$pid" 2>/dev/null
    sleep 1
    kill -KILL "$pid" 2>/dev/null
  fi
done
