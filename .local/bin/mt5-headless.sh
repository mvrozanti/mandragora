set -uo pipefail

PREFIX="${MT5_PREFIX:-$HOME/.local/share/mt5}"
export WINEPREFIX="$PREFIX/wine"
export WINEDEBUG="-all"
WINPY="$WINEPREFIX/drive_c/python/python.exe"
MT5="$WINEPREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe"
HOST="${MT5_HOST:-127.0.0.1}"
PORT="${MT5_PORT:-18812}"
DISP="${MT5_DISPLAY:-:99}"

rm -f "/tmp/.X${DISP#:}-lock"
Xvfb "$DISP" -screen 0 1280x1024x24 -nolisten tcp &
xvfb_pid=$!
export DISPLAY="$DISP"

term_pid=""
cleanup() {
  [ -n "$term_pid" ] && kill "$term_pid" 2>/dev/null
  kill "$xvfb_pid" 2>/dev/null
  return 0
}
trap cleanup EXIT

sleep 4
echo ">> launching MT5 terminal headless on $DISP (saved login auto-reconnects)"
wine "$MT5" &
term_pid=$!

sleep 25
echo ">> starting mt5linux rpyc bridge on $HOST:$PORT"
exec wine "$WINPY" -m mt5linux --host "$HOST" -p "$PORT"
