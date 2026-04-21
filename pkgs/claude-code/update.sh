#!/usr/bin/env bash
# Updates pkgs/claude-code to the latest @anthropic-ai/claude-code on npm.
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
URL="https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${VERSION}.tgz"

# 1. Source hash
echo "Fetching source hash..."
SRC_HASH=$(nix-prefetch-url --unpack --type sha256 "$URL" 2>/dev/null | tail -1)
SRC_SRI=$(nix hash convert --hash-algo sha256 --to sri "$SRC_HASH" 2>/dev/null \
          || nix hash to-sri --type sha256 "$SRC_HASH" 2>/dev/null)

# 2. Generate package-lock.json from package.json in the tarball
echo "Generating package-lock.json..."
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
curl -sL "$URL" | tar -xz -C "$TMPDIR"
# Use nix-provided npm so we don't need it globally installed
nix shell nixpkgs#nodejs --command bash -c "
  cd '$TMPDIR/package'
  npm install --package-lock-only --ignore-scripts 2>/dev/null
"
cp "$TMPDIR/package/package-lock.json" "$DIR/package-lock.json"

# 3. npmDepsHash via prefetch-npm-deps
echo "Fetching npmDepsHash..."
NPM_HASH=$(nix shell nixpkgs#prefetch-npm-deps --command prefetch-npm-deps "$DIR/package-lock.json" 2>/dev/null | tail -1)

# 4. Patch default.nix
echo "Patching default.nix..."
sed -i "s|version = \"${CURRENT}\"|version = \"${VERSION}\"|" "$DIR/default.nix"
sed -i "s|hash = \"sha256-[^\"]*\"|hash = \"${SRC_SRI}\"|" "$DIR/default.nix"
sed -i "s|npmDepsHash = \"sha256-[^\"]*\"|npmDepsHash = \"${NPM_HASH}\"|" "$DIR/default.nix"

echo "Done: claude-code $VERSION"
echo "Rebuild: sudo nixos-rebuild switch --flake /etc/nixos/mandragora#mandragora-desktop"
