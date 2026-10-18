#!/usr/bin/env bash
set -euo pipefail
state="${XDG_RUNTIME_DIR:-/tmp}/gl-fallback-watch.notified"
touch "$state"
for task in /proc/[0-9]*/task/*/comm; do
  read -r name < "$task" 2>/dev/null || continue
  [[ "$name" == llvmpipe* ]] || continue
  pid=${task#/proc/}
  pid=${pid%%/*}
  grep -qx "$pid" "$state" && continue
  read -r comm < "/proc/$pid/comm" 2>/dev/null || comm="pid $pid"
  [[ "$comm" == *.exe ]] && continue
  notify-send -u critical "Software rendering" "$comm (pid $pid) runs on llvmpipe: restart it to get the GPU back"
  echo "$pid" >> "$state"
done
