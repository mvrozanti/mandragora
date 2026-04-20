#!/usr/bin/env bash
set -eo pipefail
FLAKE="/etc/nixos/mandragora"

cd "$FLAKE"
git add -A

echo "==> Building..."
if sudo nixos-rebuild switch --flake "$FLAKE#mandragora-desktop" 2>&1 | tee /tmp/nixos-rebuild.log | grep --line-buffered -E "^(error:|building|activating|warning:)"; then
  echo ""
  echo "==> Switch successful."
  echo "    git commit -m '...' && git push"
else
  echo ""
  echo "==> FAILED. Full log: /tmp/nixos-rebuild.log" >&2
  exit 1
fi
