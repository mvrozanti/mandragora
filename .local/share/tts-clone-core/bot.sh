#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

STATE_DIR="${TTS_CLONE_STATE_DIR:-$HOME/.local/share/tts-clone-core}"
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

LD_EXTRAS=""
[ -d /run/opengl-driver/lib ] && LD_EXTRAS="$LD_EXTRAS:/run/opengl-driver/lib"
[ -n "${NIX_LD_LIBRARY_PATH:-}" ] && LD_EXTRAS="$LD_EXTRAS:$NIX_LD_LIBRARY_PATH"
[ -d /run/current-system/sw/lib ] && LD_EXTRAS="$LD_EXTRAS:/run/current-system/sw/lib"

FFMPEG_REAL=$(readlink -f "$(command -v ffmpeg)" 2>/dev/null || true)
if [ -n "$FFMPEG_REAL" ]; then
  FFMPEG_LIB="${FFMPEG_REAL%-bin/bin/ffmpeg}-lib/lib"
  [ -d "$FFMPEG_LIB" ] && LD_EXTRAS="$LD_EXTRAS:$FFMPEG_LIB"
fi

NVIDIA_LIBS=""
for sub in cublas/lib cudnn/lib cuda_runtime/lib cuda_nvrtc/lib nccl/lib; do
  d="$PY_LIB_DIR/nvidia/$sub"
  [ -d "$d" ] && NVIDIA_LIBS="$NVIDIA_LIBS:$d"
done

export LD_LIBRARY_PATH="${LD_EXTRAS#:}${NVIDIA_LIBS}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export TRITON_LIBCUDA_PATH="/run/opengl-driver/lib"

export PYTHONPATH="${PYTHONPATH:+$PYTHONPATH:}/etc/nixos/mandragora/.local/share/gpu-lock"

export HF_HOME="${HF_HOME:-$STATE_DIR/hf-cache}"

HF_SECRET_PATH="/run/secrets/huggingface/read_token"
if [ -z "${HF_TOKEN:-}" ] && [ -r "$HF_SECRET_PATH" ]; then
  HF_TOKEN="$(cat "$HF_SECRET_PATH")"
fi
[ -n "${HF_TOKEN:-}" ] && export HF_TOKEN HUGGING_FACE_HUB_TOKEN="$HF_TOKEN"

exec "$VENV/bin/python" "$PWD/main.py"
