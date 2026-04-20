#!/usr/bin/env bash
set -eo pipefail
FLAKE="/etc/nixos/mandragora"

cd "$FLAKE"

git add -A

DIFF=$(git diff --cached)
STAT=$(git diff --cached --stat)

if [ -z "$DIFF" ]; then
  echo "==> No uncommitted changes."
fi

TMPFILE=$(mktemp /tmp/mandragora-commit-XXXXXX)
trap 'rm -f "$TMPFILE"' EXIT

{
  echo "switch"
  echo ""
  echo "# Changes (save with message to apply, empty file to abort):"
  echo "#"
  echo "$STAT" | sed 's/^/# /'
  echo "#"
  echo "$DIFF" | sed 's/^/# /'
} > "$TMPFILE"

${EDITOR:-nano} "$TMPFILE"

MSG=$(grep -v '^#' "$TMPFILE" | sed '/^[[:space:]]*$/d')
if [ -z "$MSG" ]; then
  echo "==> Aborted."
  git restore --staged .
  exit 0
fi

git commit -m "$MSG"

echo ""
echo "==> Building..."
if sudo nixos-rebuild switch --flake "$FLAKE#mandragora-desktop" 2>&1 | tee /tmp/nixos-rebuild.log | grep --line-buffered -E "^(error:|building|activating|warning:)"; then
  echo ""
  echo "==> Switch successful. Pushing..."
  git push
  echo "==> Done."
else
  echo ""
  echo "==> FAILED. Rolling back commit. Full log: /tmp/nixos-rebuild.log" >&2
  git reset HEAD~1
  exit 1
fi
