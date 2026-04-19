#!/usr/bin/env bash
set -e
FLAKE="$HOME/mandragora"

cd "$FLAKE"
git add -A
sudo nixos-rebuild switch --flake "$FLAKE#mandragora-desktop"
echo ""
echo "  Switch successful. Commit when ready:"
echo "  git -C $FLAKE commit -m '...' && git push"
