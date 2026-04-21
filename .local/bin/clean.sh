#!/usr/bin/env bash
# clean - NixOS disk space cleanup
# Usage: clean [GENERATIONS] [-a|--all] [-o|--optimize]
#   GENERATIONS  keep last N generations (interactive picker if omitted)
#   -a           delete ALL old generations
#   -o           also run nix store optimise (slow deduplication)

KEEP=""
OPTIMIZE=false
for arg in "$@"; do
  case "$arg" in
    -a|--all) KEEP=0 ;;
    -o|--optimize) OPTIMIZE=true ;;
    [0-9]*) KEEP="$arg" ;;
  esac
done

echo "==> Before:"
df -h / | tail -1

echo ""
echo "==> System generations:"
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system

if [[ -z "$KEEP" ]]; then
  total=$(sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | wc -l)
  echo ""
  echo "You have $total generations. How many to keep?"
  echo "  0) Delete ALL old generations"
  echo "  1) Keep only the current generation"
  echo "  5) Keep last 5"
  echo " 10) Keep last 10"
  echo "  *) Enter a custom number"
  echo ""
  read -rp "Generations to keep [5]: " KEEP
  KEEP=${KEEP:-5}
fi

echo ""
if [[ "$KEEP" -eq 0 ]]; then
  echo "==> Collecting garbage (all old generations)..."
  sudo nix-collect-garbage -d
  nix-collect-garbage -d
else
  echo "==> Collecting garbage (keeping last $KEEP generations)..."
  sudo nix-env --delete-generations "+$KEEP" --profile /nix/var/nix/profiles/system
  nix-env --delete-generations "+$KEEP"
  nix-collect-garbage
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
