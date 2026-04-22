#!/usr/bin/env bash
FLAKE="/etc/nixos/mandragora"
cd "$FLAKE"
git status
echo ""
git diff HEAD
