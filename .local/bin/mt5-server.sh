set -euo pipefail

PREFIX="${MT5_PREFIX:-$HOME/.local/share/mt5}"
export WINEPREFIX="$PREFIX/wine"
export WINEDEBUG="-all"
WINPY="$WINEPREFIX/drive_c/python/python.exe"
LINUX_VENV="$PREFIX/linux-venv"
HOST="${MT5_HOST:-127.0.0.1}"
PORT="${MT5_PORT:-18812}"

if [ ! -x "$LINUX_VENV/bin/python" ]; then
  echo "bridge venv missing — run mt5-bootstrap first" >&2
  exit 1
fi

echo ">> starting mt5linux rpyc bridge in wine python on $HOST:$PORT"
exec wine "$WINPY" -m mt5linux --host "$HOST" -p "$PORT"
