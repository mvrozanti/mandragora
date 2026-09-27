#!/usr/bin/env bash
set -uo pipefail

FLAKE="${MANDRAGORA_REPO:-/etc/nixos/mandragora}"
PKGREL="nix/pkgs/claude-code/default.nix"
NOTIFY="${MANDRAGORA_NOTIFY_BIN:-telegram-notify}"
REGISTRY="https://registry.npmjs.org/@anthropic-ai/claude-code"
RUNBASE="${XDG_RUNTIME_DIR:-}"
if [ -z "$RUNBASE" ] || [ ! -w "$RUNBASE" ]; then RUNBASE="/tmp"; fi
WT="$RUNBASE/claude-code-update-wt"
BRANCH="chore/claude-code-auto"
CHECK_ONLY=0

for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=1 ;;
    -h|--help)
      cat <<'EOF'
claude-code-update — bump the pinned claude-code, rebuild, commit, push.

Compares nix/pkgs/claude-code/default.nix against the npm `latest` tag.
On a new version it prefetches both arch tarballs, edits the pin in a
throwaway worktree and hands off to mandragora-switch, which audits,
builds, switches, promotes to master and pushes.

Usage: claude-code-update [--check]
  --check   report installed vs latest and exit
EOF
      exit 0 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

notify() { "$NOTIFY" "$@" >/dev/null 2>&1 || true; }

current=$(sed -n 's/^  version = "\([^"]*\)";$/\1/p' "$FLAKE/$PKGREL" | head -1)
if [ -z "$current" ]; then
  echo "could not read pinned version from $FLAKE/$PKGREL" >&2
  exit 1
fi

latest=$(curl -fsSL --max-time 30 "$REGISTRY/latest" 2>/dev/null | jq -r '.version // empty')
if ! printf '%s' "$latest" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "could not resolve latest claude-code version from npm" >&2
  exit 1
fi

echo "installed: $current"
echo "latest:    $latest"

if [ "$CHECK_ONLY" -eq 1 ]; then exit 0; fi
if [ "$latest" = "$current" ]; then
  echo "already current"
  exit 0
fi

sri_for() {
  local npm_arch="$1" h
  h=$(nix-prefetch-url --unpack --type sha256 \
        "$REGISTRY-$npm_arch/-/claude-code-$npm_arch-$latest.tgz" 2>/dev/null | tail -1)
  [ -n "$h" ] || return 1
  nix hash convert --hash-algo sha256 --to sri "$h"
}

echo "prefetching $latest..."
if ! X64=$(sri_for linux-x64) || ! ARM=$(sri_for linux-arm64); then
  notify "claude-code $latest: prefetch failed, pin left at $current"
  echo "prefetch failed" >&2
  exit 1
fi

cleanup() {
  git -C "$FLAKE" worktree remove --force "$WT" 2>/dev/null || rm -rf "$WT"
  git -C "$FLAKE" worktree prune 2>/dev/null || true
  git -C "$FLAKE" branch -D "$BRANCH" 2>/dev/null || true
}
trap cleanup EXIT

git -C "$FLAKE" fetch origin >/dev/null 2>&1 || true
rm -rf "$WT"
git -C "$FLAKE" worktree prune 2>/dev/null || true
git -C "$FLAKE" branch -D "$BRANCH" >/dev/null 2>&1 || true
if ! git -C "$FLAKE" worktree add -b "$BRANCH" "$WT" refs/heads/master >/dev/null 2>&1; then
  echo "could not create worktree at $WT" >&2
  exit 1
fi

PKG="$WT/$PKGREL"
awk -v ver="$latest" -v x64="$X64" -v arm="$ARM" '
  /npmArch = "linux-x64";/ { print; if ((getline l) > 0) { sub(/sha256-[^"]*/, x64, l); print l } next }
  /npmArch = "linux-arm64";/ { print; if ((getline l) > 0) { sub(/sha256-[^"]*/, arm, l); print l } next }
  /^  version = "[0-9][^"]*";$/ { sub(/"[0-9][^"]*"/, "\"" ver "\""); print; next }
  { print }
' "$PKG" > "$PKG.new" && mv "$PKG.new" "$PKG"

if git -C "$WT" diff --quiet -- "$PKGREL"; then
  echo "pin edit produced no change; aborting" >&2
  notify "claude-code $latest: pin rewrite matched nothing in $PKGREL — update the script"
  exit 1
fi

echo "building claude-code $latest..."
out=$(nix build --no-link --print-out-paths \
        "$WT#nixosConfigurations.mandragora-desktop.pkgs.claude-code" 2>&1 | tail -1)
if [ ! -x "$out/bin/claude" ]; then
  notify "claude-code $latest: package build failed, pin left at $current"
  echo "build failed: $out" >&2
  exit 1
fi
built=$("$out/bin/claude" --version 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')
if [ "$built" != "$latest" ]; then
  notify "claude-code $latest: built binary reports ${built:-nothing}, pin left at $current"
  echo "version mismatch: built $built" >&2
  exit 1
fi

cd "$WT" || exit 1
SWITCHLOG="$RUNBASE/claude-code-update-switch.log"
mandragora-switch "chore(claude-code): bump to $latest" > "$SWITCHLOG" 2>&1
rc=$?
tail -5 "$SWITCHLOG"

if [ "$rc" -ne 0 ]; then
  if grep -q "another mandragora-switch is in progress\|nixos-rebuild is already running" "$SWITCHLOG"; then
    echo "switch busy; retrying on the next timer"
    exit 0
  fi
  reason=$(grep -m1 -E "^==> (ABORTED|FAILED)" "$SWITCHLOG" | cut -c1-160)
  notify "claude-code $current -> $latest: switch failed. ${reason:-see $SWITCHLOG}"
  exit "$rc"
fi

notify "claude-code updated $current -> $latest and switched on mandragora-desktop."
echo "updated $current -> $latest"
