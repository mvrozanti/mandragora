#!/usr/bin/env bash
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

fetch_sri() {
  local npm_arch="$1"
  local url="https://registry.npmjs.org/@anthropic-ai/claude-code-${npm_arch}/-/claude-code-${npm_arch}-${VERSION}.tgz"
  echo "Fetching ${npm_arch} hash..." >&2
  local raw
  raw=$(nix-prefetch-url --unpack --type sha256 "$url" 2>/dev/null | tail -1)
  nix hash convert --hash-algo sha256 --to sri "$raw" 2>/dev/null \
    || nix hash to-sri --type sha256 "$raw"
}

X64_SRI=$(fetch_sri linux-x64)
ARM64_SRI=$(fetch_sri linux-arm64)
DARWIN_SRI=$(fetch_sri darwin-arm64)

echo "Patching default.nix..."
python3 - "$DIR/default.nix" "$VERSION" "$X64_SRI" "$ARM64_SRI" "$DARWIN_SRI" <<'PY'
import re, sys, pathlib
path, version, x64, arm64, darwin = sys.argv[1:]
p = pathlib.Path(path)
s = p.read_text()
s = re.sub(r'version = "[^"]+";', f'version = "{version}";', s, count=1)
s = re.sub(r'("x86_64-linux"\s*=\s*\{[^}]*?hash\s*=\s*")[^"]+"', lambda m: m.group(1) + x64 + '"', s, count=1, flags=re.S)
s = re.sub(r'("aarch64-linux"\s*=\s*\{[^}]*?hash\s*=\s*")[^"]+"', lambda m: m.group(1) + arm64 + '"', s, count=1, flags=re.S)
s = re.sub(r'("aarch64-darwin"\s*=\s*\{[^}]*?hash\s*=\s*")[^"]+"', lambda m: m.group(1) + darwin + '"', s, count=1, flags=re.S)
p.write_text(s)
PY

echo "Done: claude-code $VERSION"
echo "Rebuild: sudo nixos-rebuild switch --flake /etc/nixos/mandragora#mandragora-desktop"
