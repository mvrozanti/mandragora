#!/usr/bin/env bash
set -euo pipefail

# uaRO launcher: patcher → game. Wine prefix isolated under ~/Games/uaro/prefix.

PREFIX="${WINEPREFIX:-$HOME/Games/uaro/prefix}"
GAMEDIR="$PREFIX/drive_c/uaRO"
LAUNCH_EXE="${1:-patcher}"

case "$LAUNCH_EXE" in
  patcher) EXE="UaRo Patcher.exe" ;;
  game)    EXE="uaRO.exe" ;;
  setup)   EXE="setup.exe" ;;
  *)       EXE="$LAUNCH_EXE" ;;
esac

[[ -f "$GAMEDIR/$EXE" ]] || { echo "missing $GAMEDIR/$EXE" >&2; exit 1; }

cd "$GAMEDIR"
exec env \
  WINEPREFIX="$PREFIX" \
  WINEARCH=win64 \
  WINEDEBUG=-all \
  WINEDLLOVERRIDES='mscoree=;mshtml=' \
  DXVK_HUD=0 \
  __GL_SHADER_DISK_CACHE=1 \
  __NV_PRIME_RENDER_OFFLOAD=1 \
  gamemoderun wine "$EXE"
