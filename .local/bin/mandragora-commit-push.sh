#!/usr/bin/env bash
set -eo pipefail
FLAKE="/etc/nixos/mandragora"

cd "$FLAKE"

echo "==> Fetching origin..."
if ! git fetch origin; then
  echo "==> WARNING: git fetch failed. Proceeding without sync check." >&2
elif [ "$(git rev-list --count HEAD..origin/master)" -gt 0 ]; then
  echo "==> Remote is ahead by $(git rev-list --count HEAD..origin/master) commit(s). Rebasing..."
  if ! git pull --rebase --autostash origin master; then
    echo "==> FAILED: rebase conflict. Resolve manually then re-run." >&2
    exit 1
  fi
fi

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
if ! git push; then
  echo "==> FAILED: push was rejected. Your local commit is NOT on origin." >&2
  echo "==> Run: git pull --rebase && git push" >&2
  exit 1
fi
echo "==> Done."
