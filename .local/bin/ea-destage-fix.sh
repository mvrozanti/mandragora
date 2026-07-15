#!/usr/bin/env bash
set -uo pipefail

DEFAULT_BASES=(
  "$HOME/Games/origin/drive_c/Program Files/Electronic Arts/EA Desktop"
  "$HOME/Games/ea-app/drive_c/Program Files/Electronic Arts/EA Desktop"
)

log="${XDG_STATE_HOME:-$HOME/.local/state}/ea-destage-fix.log"
mkdir -p "$(dirname "$log")"
say() { printf '[%s] %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$*" | tee -a "$log" >&2; }

if pgrep -f 'EADesktop\.exe|EABackgroundService\.exe' >/dev/null 2>&1; then
  say "EA process live — skipping (unsafe to swap while running)"
  exit 0
fi

fix_base() {
  local base="$1"
  [ -d "$base" ] || return 0

  local staged="" d
  while IFS= read -r d; do
    [ -f "$d/EA Desktop/EADesktop.exe" ] && staged="$d"
  done < <(find "$base" -maxdepth 1 -mindepth 1 -type d \
             -regextype posix-extended -regex '.*/[0-9]+(\.[0-9]+)+-[0-9]+$' 2>/dev/null)

  [ -n "$staged" ] || return 0

  local live_ver new_ver prefix_root archive bak
  live_ver="$(cat "$base/EA Desktop/version.properties" 2>/dev/null || echo unknown)"
  new_ver="$(cat "$staged/EA Desktop/version.properties" 2>/dev/null || echo unknown)"
  prefix_root="${base%%/drive_c/*}"
  archive="$prefix_root/_destage_backup/$(basename "$staged")"
  say "staged update found in $base: live[$live_ver] -> new[$new_ver]"

  mkdir -p "$archive"
  bak="$base/EA Desktop.bak-$live_ver"
  [ -e "$bak" ] && bak="$bak-$(date +%s)"

  mv "$base/EA Desktop" "$bak" || { say "FAIL backing up live dir"; return 1; }
  mv "$staged/EA Desktop" "$base/EA Desktop" || { say "FAIL swapping staged in"; return 1; }
  mv "$staged" "$archive/" 2>/dev/null || true
  [ -e "$staged.zip" ]     && mv "$staged.zip" "$archive/" 2>/dev/null || true
  [ -e "$staged.zip.sig" ] && mv "$staged.zip.sig" "$archive/" 2>/dev/null || true

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
