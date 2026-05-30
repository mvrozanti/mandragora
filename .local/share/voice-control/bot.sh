#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export VOICE_CONTROL_STATIC_DIR="${VOICE_CONTROL_STATIC_DIR:-$here/static}"
exec python3 "$here/main.py"
