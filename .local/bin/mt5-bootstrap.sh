set -euo pipefail

PREFIX="${MT5_PREFIX:-$HOME/.local/share/mt5}"
export WINEPREFIX="$PREFIX/wine"
export WINEARCH="win64"
export WINEDEBUG="-all"
WINPY="$WINEPREFIX/drive_c/python/python.exe"
LINUX_VENV="$PREFIX/linux-venv"
MARK_WINE="$PREFIX/.wine-done"
MARK_MT5="$PREFIX/.mt5-installed"
PYVER="3.11.9"

mkdir -p "$PREFIX"

if [ ! -f "$MARK_WINE" ]; then
  echo ">> initializing wine prefix at $WINEPREFIX"
  wineboot --init
  touch "$MARK_WINE"
fi

if ! wine "$WINPY" --version >/dev/null 2>&1; then
  echo ">> installing windows python $PYVER into the wine prefix"
  curl -fL -o "$PREFIX/py-setup.exe" "https://www.python.org/ftp/python/$PYVER/python-$PYVER-amd64.exe"
  wine "$PREFIX/py-setup.exe" /quiet InstallAllUsers=1 PrependPath=1 Include_pip=1 'TargetDir=C:\python'
fi

echo ">> installing MetaTrader5 + mt5linux into the wine python"
wine "$WINPY" -m pip install --no-input --upgrade pip MetaTrader5 mt5linux rpyc

if [ ! -d "$LINUX_VENV" ]; then
  echo ">> creating linux bridge venv at $LINUX_VENV"
  uv venv "$LINUX_VENV"
fi
echo ">> installing mt5linux + pandas into the linux bridge venv"
uv pip install --python "$LINUX_VENV/bin/python" mt5linux rpyc pandas pyarrow

if [ ! -f "$MARK_MT5" ]; then
  echo ">> downloading + installing MetaTrader 5 terminal (silent /auto)"
  curl -fL -o "$PREFIX/mt5setup.exe" "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe"
  wine "$PREFIX/mt5setup.exe" /auto || true
  touch "$MARK_MT5"
fi

echo ""
echo "bootstrap complete."
echo "  bridge venv python : $LINUX_VENV/bin/python"
echo "  open the terminal  : wine \"\$WINEPREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe\""
echo "  log into your broker ONCE in the terminal (investor/read-only password is enough),"
echo "  then: mt5-server  +  the harvester against 127.0.0.1:18812"
