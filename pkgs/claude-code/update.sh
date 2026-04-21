#!/usr/bin/env bash
# Updates pkgs/claude-code/default.nix to the latest @anthropic-ai/claude-code on npm.
# Fetches the linux-x64 native binary package directly (no npm build required).
# Run from anywhere; resolves its own directory.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Fetching latest version from npm..."
VERSION=$(curl -s https://registry.npmjs.org/@anthropic-ai/claude-code/latest | jq -r .version)
CURRENT=$(grep -oP 'version = "\K[^"]+' "$DIR/default.nix")

if [[ "$VERSION" == "$CURRENT" ]]; then
  echo "Already at latest: $VERSION"
  exit 0
fi

echo "Updating $CURRENT -> $VERSION"

NATIVE_URL="https://registry.npmjs.org/@anthropic-ai/claude-code-linux-x64/-/claude-code-linux-x64-${VERSION}.tgz"

echo "Fetching linux-x64 native binary hash..."
RAW_HASH=$(nix-prefetch-url --unpack --type sha256 "$NATIVE_URL" 2>/dev/null | tail -1)
SRI_HASH=$(nix hash convert --hash-algo sha256 --to sri "$RAW_HASH" 2>/dev/null \
           || nix hash to-sri --type sha256 "$RAW_HASH" 2>/dev/null)

echo "Patching default.nix..."
sed -i "s|version = \"${CURRENT}\"|version = \"${VERSION}\"|" "$DIR/default.nix"
sed -i "s|hash = \"sha256-[^\"]*\"|hash = \"${SRI_HASH}\"|" "$DIR/default.nix"

echo "Done: claude-code $VERSION"
echo "Rebuild: sudo nixos-rebuild switch --flake /etc/nixos/mandragora#mandragora-desktop"
