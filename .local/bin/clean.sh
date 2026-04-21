#!/usr/bin/env bash
# clean - NixOS disk space cleanup
# Usage: clean [-a|--all] [-o|--optimize]
#   -a  delete ALL old generations (default: older than 7d)
#   -o  also run nix store optimise (slow deduplication)

ALL=false
OPTIMIZE=false
for arg in "$@"; do
  case "$arg" in
    -a|--all) ALL=true ;;
    -o|--optimize) OPTIMIZE=true ;;
  esac
done

echo "==> Before:"
df -h / | tail -1

echo ""
echo "==> System generations:"
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system

echo ""
if $ALL; then
  echo "==> Collecting garbage (all old generations)..."
  sudo nix-collect-garbage -d
  nix-collect-garbage -d
else
  echo "==> Collecting garbage (older than 7 days)..."
  sudo nix-collect-garbage --delete-older-than 7d
  nix-collect-garbage --delete-older-than 7d
fi

echo ""
echo "==> Vacuuming journal..."
sudo journalctl --vacuum-size=512M

if compgen -G "/var/lib/systemd/coredump/core.*" > /dev/null 2>&1; then
  echo "==> Removing coredumps..."
  sudo rm -rf /var/lib/systemd/coredump/core.*
fi

if command -v trash-empty &>/dev/null; then
  echo "==> Emptying trash..."
  trash-empty
fi

if $OPTIMIZE; then
  echo ""
  echo "==> Optimising nix store (deduplication, this is slow)..."
  nix store optimise
fi

echo ""
echo "==> After:"
df -h / | tail -1
