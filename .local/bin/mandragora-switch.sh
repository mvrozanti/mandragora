#!/usr/bin/env bash
set -eo pipefail
FLAKE="/etc/nixos/mandragora"

cd "$FLAKE"

DIFF=$(git diff HEAD)
STAT=$(git diff HEAD --stat)

if [ -z "$DIFF" ]; then
  echo "==> No uncommitted changes."
else
  echo "$STAT"
  echo ""
  echo "$DIFF" | ${PAGER:-less -R}
fi

printf "==> Commit message (empty to abort): "
read -r MSG
[ -n "$MSG" ] || exit 0

git add -A
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
