#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLAKE_TARGET="${1:-mandragora-desktop}"

nixos-install \
  --root /mnt \
  --flake "${REPO_DIR}#${FLAKE_TARGET}" \
  --no-root-passwd
