#!/usr/bin/env bash
set -uo pipefail

DEFAULT_BASES=(
  "$HOME/Games/origin/drive_c/Program Files/Electronic Arts/EA Desktop"
  "$HOME/Games/ea-app/drive_c/Program Files/Electronic Arts/EA Desktop"
)

log="${XDG_STATE_HOME:-$HOME/.local/state}/ea-destage-fix.log"
mkdir -p "$(dirname "$log")"
say() { printf '[%s] %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$*" | tee -a "$log" >&2; }

ea_pids_in_prefix() {
  local prefix_root="$1" pid
  for pid in $(pgrep -f 'EADesktop\.exe|EABackgroundService\.exe|EACefSubProcess\.exe|EALocalHostSvc\.exe|OriginWebHelperService\.exe|EAConnect' 2>/dev/null); do
    [ "$pid" = "$$" ] && continue
    grep -qxz "WINEPREFIX=$prefix_root" "/proc/$pid/environ" 2>/dev/null && printf '%s\n' "$pid"
  done
}

wineserver_pids_in_prefix() {
  local prefix_root="$1" pid
  for pid in $(pgrep -x wineserver 2>/dev/null); do
    grep -qxz "WINEPREFIX=$prefix_root" "/proc/$pid/environ" 2>/dev/null && printf '%s\n' "$pid"
  done
}

reap_prefix() {
  local prefix_root="$1" sig _
  local -a pids
  mapfile -t pids < <(ea_pids_in_prefix "$prefix_root")
  [ "${#pids[@]}" -gt 0 ] || return 0
  say "stale EA processes in $prefix_root (pids: ${pids[*]}) — a swap is pending, terminating them"
  for sig in TERM TERM KILL; do
    mapfile -t pids < <(ea_pids_in_prefix "$prefix_root")
    [ "${#pids[@]}" -gt 0 ] || break
    kill "-$sig" "${pids[@]}" 2>/dev/null
    for _ in 1 2 3; do
      mapfile -t pids < <(ea_pids_in_prefix "$prefix_root")
      [ "${#pids[@]}" -gt 0 ] || break
      sleep 1
    done
  done
  mapfile -t pids < <(wineserver_pids_in_prefix "$prefix_root")
  if [ "${#pids[@]}" -gt 0 ]; then
    say "reaping stale wineserver in $prefix_root (pids: ${pids[*]})"
    kill -9 "${pids[@]}" 2>/dev/null
    sleep 1
  fi
  mapfile -t pids < <(ea_pids_in_prefix "$prefix_root")
  [ "${#pids[@]}" -eq 0 ]
}

fix_base() {
  local base="$1"
  [ -d "$base" ] || return 0

  local prefix_root d
  prefix_root="${base%%/drive_c/*}"

  local -a staged=()
  while IFS= read -r d; do
    [ -f "$base/$d/EA Desktop/EADesktop.exe" ] && staged+=("$d")
  done < <(find "$base" -maxdepth 1 -mindepth 1 -type d \
             -regextype posix-extended -regex '.*/[0-9]+(\.[0-9]+)+-[0-9]+$' \
             -printf '%f\n' 2>/dev/null | sort -V)

  [ "${#staged[@]}" -gt 0 ] || return 0

  if ! reap_prefix "$prefix_root"; then
    say "EA processes survived termination in $prefix_root — aborting swap to stay safe"
    return 1
  fi

  local newest live_ver new_ver archive bak s
  newest="${staged[-1]}"
  live_ver="$(cat "$base/EA Desktop/version.properties" 2>/dev/null || echo unknown)"
  new_ver="$(cat "$base/$newest/EA Desktop/version.properties" 2>/dev/null || echo unknown)"
  archive="$prefix_root/_destage_backup"
  say "destaging $base: live[$live_ver] -> new[$new_ver] (${#staged[@]} staged dir(s): ${staged[*]})"

  mkdir -p "$archive"
  bak="$base/EA Desktop.bak-$live_ver"
  [ -e "$bak" ] && bak="$bak-$(date +%s)"

  mv "$base/EA Desktop" "$bak" || { say "FAIL backing up live dir"; return 1; }
  mv "$base/$newest/EA Desktop" "$base/EA Desktop" || { say "FAIL swapping staged in"; return 1; }

  for s in "${staged[@]}"; do
    [ -e "$base/$s" ]         && mv "$base/$s" "$archive/"         2>/dev/null || true
    [ -e "$base/$s.zip" ]     && mv "$base/$s.zip" "$archive/"     2>/dev/null || true
    [ -e "$base/$s.zip.sig" ] && mv "$base/$s.zip.sig" "$archive/" 2>/dev/null || true
  done

  local keep=0 old
  while IFS= read -r old; do
    keep=$((keep + 1))
    [ "$keep" -gt 2 ] && rm -rf "$old" && say "pruned old backup $old"
  done < <(ls -dt "$base"/EA\ Desktop.bak-* 2>/dev/null)

  say "applied — $base/EA Desktop now $(cat "$base/EA Desktop/version.properties" 2>/dev/null)"
}

if [ "$#" -gt 0 ]; then
  for b in "$@"; do fix_base "$b"; done
else
  for b in "${DEFAULT_BASES[@]}"; do fix_base "$b"; done
fi
exit 0
