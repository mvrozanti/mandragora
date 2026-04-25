#!/usr/bin/env bash
FLAKE="/etc/nixos/mandragora"
cd "$FLAKE"
git status
echo ""
echo -e "\e[1;33m--- Uncommitted Changes ---\e[0m"
git diff HEAD
echo ""
echo -e "\e[1;33m--- Last Commit Changes (HEAD~1 -> HEAD) ---\e[0m"
git diff HEAD~1 HEAD
