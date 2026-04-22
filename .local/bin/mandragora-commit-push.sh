#!/usr/bin/env bash
set -eo pipefail
FLAKE="/etc/nixos/mandragora"

cd "$FLAKE"

git add -A

DIFF=$(git diff --cached)
STAT=$(git diff --cached --stat)

if [ -z "$DIFF" ]; then
  echo "==> No uncommitted changes."
  exit 0
fi

MSG="${*:-switch}"
TMPFILE=$(mktemp /tmp/mandragora-commit-XXXXXX)
trap 'rm -f "$TMPFILE"' EXIT

{
  echo "$MSG"
  echo ""
  echo "# Changes (save with message to apply, empty file to abort):"
  echo "#"
  echo "$STAT" | sed 's/^/# /'
  echo "#"
  echo "$DIFF" | sed 's/^/# /'
} > "$TMPFILE"

${EDITOR:-nvim} "$TMPFILE"

MSG=$(grep -v '^#' "$TMPFILE" | sed '/^[[:space:]]*$/d')
if [ -z "$MSG" ]; then
  echo "==> Aborted."
  exit 0
fi

git commit -m "$MSG"
echo "==> Pushing..."
git push
echo "==> Done."
