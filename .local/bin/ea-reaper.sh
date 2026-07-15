#!/usr/bin/env bash
set -uo pipefail

PREFIXES=(/home/m/Games/origin /home/m/Games/ea-app)

state="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ea-reaper"
log="${XDG_STATE_HOME:-$HOME/.local/state}/ea-reaper.log"
mkdir -p "$state" "$(dirname "$log")"
say() { printf '[%s] %s\n' "$(date +%FT%T%z)" "$*" >>"$log"; }

pgrep -f lutris-wrapped >/dev/null 2>&1 || exit 0

WL='EABackgroundService\.exe|EALocalHostSvc\.exe|EACefSubProcess\.exe|EAConnect_microsoft\.exe|OriginWebHelperService\.exe|EACrashReporter\.exe|EAGEP\.exe|Link2EA\.exe|IGOProxy(32|64)\.exe|services\.exe|winedevice\.exe|plugplay\.exe|explorer\.exe|svchost\.exe|rpcss\.exe|conhost\.exe|start\.exe|wineboot\.exe|winedbg\.exe|tabtip\.exe|rundll32\.exe'

reap_prefix() {
  local pfx="$1"
  local stamp pdir pid cmd exe server foreground pids
  stamp="$state/$(printf '%s' "$pfx" | tr '/ ' '__').armed"

  pids=()
  for pdir in /proc/[0-9]*; do
    if grep -qzsF "WINEPREFIX=$pfx" "$pdir/environ" 2>/dev/null; then
      pids+=("${pdir#/proc/}")
    fi
  done
  if [ "${#pids[@]}" -eq 0 ]; then rm -f "$stamp"; return; fi

  foreground=0
  server=""
  for pid in "${pids[@]}"; do
    [ "$(cat "/proc/$pid/comm" 2>/dev/null)" = "wineserver" ] && server="$pid"
    cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
    while IFS= read -r exe; do
      [ -z "$exe" ] && continue
      exe=${exe##*\\}
      exe=${exe##*/}
      printf '%s' "$exe" | grep -qiE "^($WL)$" || foreground=1
    done < <(printf '%s\n' "$cmd" | grep -oiE '[A-Za-z0-9_.-]+\.exe')
  done

  if [ "$foreground" -eq 1 ]; then rm -f "$stamp"; return; fi
  if [ -z "$server" ]; then rm -f "$stamp"; return; fi

  if [ ! -e "$stamp" ]; then
    : > "$stamp"
    say "armed: orphaned session in $pfx (server=$server pids=${pids[*]})"
    return
  fi

  say "reaping orphaned wine session in $pfx (server=$server pids=${pids[*]})"
  kill -TERM "$server" 2>/dev/null
  sleep 2
  for pid in "${pids[@]}"; do kill -KILL "$pid" 2>/dev/null; done
  rm -f "$stamp"
}

for p in "${PREFIXES[@]}"; do reap_prefix "$p"; done
