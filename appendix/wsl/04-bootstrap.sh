#!/usr/bin/env bash
# Run inside NixOS-WSL (`wsl -d NixOS bash 04-bootstrap.sh`).
# Clones mandragora and switches to the mandragora-wsl host.

set -eo pipefail

# Pick up nix paths even when invoked from a non-login shell.
if [ -f /etc/profile ]; then set +u; . /etc/profile; set -u; fi
export PATH="/run/current-system/sw/bin:/run/wrappers/bin:$HOME/.nix-profile/bin:$PATH"
set -u

REPO_URL="${MANDRAGORA_REPO:-https://github.com/mvrozanti/mandragora.git}"
REPO_DIR="${MANDRAGORA_DIR:-/etc/nixos/mandragora}"

echo '[1/4] ensure git + nix flakes are usable'
if ! command -v git >/dev/null 2>&1; then
    nix-env -iA nixos.git
fi

echo '[2/4] clone mandragora'
if [ ! -d "$REPO_DIR/.git" ]; then
    sudo mkdir -p "$(dirname "$REPO_DIR")"
    sudo chown "$USER:users" "$(dirname "$REPO_DIR")"
    git clone "$REPO_URL" "$REPO_DIR"
else
    git -C "$REPO_DIR" pull --ff-only
fi

echo '[3/4] build mandragora-wsl host'
sudo nixos-rebuild switch \
    --flake "$REPO_DIR#mandragora-wsl" \
    --impure

echo '[4/4] sanity'
echo "active generation: $(nixos-version)"
echo 'mandragora-wsl bootstrap complete.'
