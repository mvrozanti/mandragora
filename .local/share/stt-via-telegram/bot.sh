#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

STATE_DIR="${STT_VIA_TELEGRAM_STATE_DIR:-$HOME/.local/share/stt-via-telegram}"
VENV="$STATE_DIR/venv"
mkdir -p "$STATE_DIR"

if [ ! -x "$VENV/bin/python" ]; then
  echo ">> bootstrapping uv venv at $VENV" >&2
  uv venv --seed "$VENV"
fi

PYPROJECT="$PWD/pyproject.toml"
STAMP="$VENV/.pyproject.sha256"
NEW_HASH=$(sha256sum "$PYPROJECT" | cut -d' ' -f1)
if [ ! -f "$STAMP" ] || [ "$(cat "$STAMP")" != "$NEW_HASH" ]; then
  echo ">> installing/updating deps" >&2
  uv pip install --python "$VENV/bin/python" -r "$PYPROJECT"
  echo "$NEW_HASH" > "$STAMP"
fi

PY_LIB_DIR=$(echo "$VENV"/lib/python*/site-packages | awk '{print $1}')

# NixOS library stitching for nvidia + system libs (mirrors im-gen pattern).
LD_EXTRAS=""
[ -d /run/opengl-driver/lib ] && LD_EXTRAS="$LD_EXTRAS:/run/opengl-driver/lib"
[ -n "${NIX_LD_LIBRARY_PATH:-}" ] && LD_EXTRAS="$LD_EXTRAS:$NIX_LD_LIBRARY_PATH"
[ -d /run/current-system/sw/lib ] && LD_EXTRAS="$LD_EXTRAS:/run/current-system/sw/lib"

# Pull cuBLAS + cuDNN from the venv-installed nvidia wheels for ctranslate2.
NVIDIA_LIBS=""
for sub in cublas/lib cudnn/lib; do
  d="$PY_LIB_DIR/nvidia/$sub"
  [ -d "$d" ] && NVIDIA_LIBS="$NVIDIA_LIBS:$d"
done

export LD_LIBRARY_PATH="${LD_EXTRAS#:}${NVIDIA_LIBS}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# Make gpu_lock importable.
export PYTHONPATH="${PYTHONPATH:+$PYTHONPATH:}/etc/nixos/mandragora/.local/share/gpu-lock"

# Cache HF models inside the state dir, not $HOME.
export HF_HOME="${HF_HOME:-$STATE_DIR/hf-cache}"

exec "$VENV/bin/python" "$PWD/main.py"
