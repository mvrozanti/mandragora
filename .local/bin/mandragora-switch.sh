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

if git diff --cached --quiet; then
  echo "==> No uncommitted changes."
fi

# Handle the "skip interactive diff" flag
SKIP_EDIT=0
if [[ "$*" == *"!"* ]]; then
  SKIP_EDIT=1
  # Remove the ! from the arguments
  ARGS=("${@/!/}")
  MSG="${ARGS[*]:-switch}"
else
  MSG="${*:-switch}"
fi

if [ "$SKIP_EDIT" -eq 1 ]; then
  # If ! is passed, we treat it as a "just switch" or "fast switch"
  # Per user request: "skip the interactive diff"
  # We'll set MSG to a special value to skip commit if only ! was passed
  if [ "$*" = "!" ]; then
    MSG="!"
  fi
else
  TMPFILE=$(mktemp /tmp/mandragora-commit-XXXXXX)
  trap 'rm -f "$TMPFILE"' EXIT

  {
    echo "$MSG"
    echo ""
    echo "# Changes shown in split above. Save with message to apply, empty file to abort."
  } > "$TMPFILE"

  nvim -c "terminal git --no-pager diff --cached" \
       -c "belowright 3split $TMPFILE" \
       -c "setlocal winfixheight" \
       -c "autocmd VimResized * let w=winnr() | execute bufwinnr('$TMPFILE').'wincmd w' | resize 3 | execute w.'wincmd w'" \
       -c "autocmd BufWritePost <buffer> qall" \
       -c "nnoremap <buffer> QQ :%d<CR>:w<CR>"

  MSG=$(grep -v '^#' "$TMPFILE" | sed '/^[[:space:]]*$/d')
  if [ -z "$MSG" ]; then
    echo "==> Aborted."
    git restore --staged .
    exit 0
  fi
fi

COMMIT_SKIPPED=0
if [ "$MSG" = "!" ]; then
  echo "==> Skipping commit (just switching)."
  COMMIT_SKIPPED=1
  git restore --staged .
else
  git commit -m "$MSG"
fi

echo ""
echo "==> Building..."
if sudo nixos-rebuild switch --flake "$FLAKE#mandragora-desktop" 2>&1 | tee /tmp/nixos-rebuild.log | grep --line-buffered -E "^(error:|building|activating|warning:)"; then
  echo ""
  echo "==> Switch successful."
  if [ "$COMMIT_SKIPPED" -eq 0 ]; then
    echo "==> Pushing..."
    if ! git push; then
      echo "==> FAILED: push was rejected. Your local commit is NOT on origin." >&2
      echo "==> Run: git pull --rebase && git push" >&2
      exit 1
    fi
  fi
  echo "==> Done."
else
  echo ""
  echo "==> FAILED. Full log: /tmp/nixos-rebuild.log" >&2
  if [ "$COMMIT_SKIPPED" -eq 0 ]; then
    git reset HEAD~1
  fi
  exit 1
fi
