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
  exit 0
fi

if [ -n "$*" ]; then
  MSG="$*"
else
  MSG=""
  if command -v claude >/dev/null 2>&1; then
    echo "==> Generating commit message with claude (haiku)..."
    RECENT=$(git log --oneline -20)
    DIFF=$(git diff --cached)
    PROMPT_SYSTEM='You write a single git commit subject for a personal NixOS+Hyprland dotfiles repo. The user message contains the recent commit log (for style) followed by the staged diff. Mirror the log'\''s style exactly: if the log uses Conventional Commits prefixes, use one; if it doesn'\''t, don'\''t invent one. Output exactly ONE line, <=72 chars, imperative mood, no trailing period, no quotes, no preamble, no body. Nothing else.'
    PAYLOAD=$(printf '## RECENT LOG (style reference)\n%s\n\n## STAGED DIFF\n%s\n' "$RECENT" "$DIFF")
    if GENERATED=$(printf '%s' "$PAYLOAD" | timeout 30 claude -p --model claude-haiku-4-5 --bare --append-system-prompt "$PROMPT_SYSTEM" "Write the commit subject for the staged diff." 2>/dev/null); then
      MSG=$(printf '%s' "$GENERATED" | sed -n '1p' | tr -d '\r')
    fi
  fi
  if [ -z "$MSG" ]; then
    echo "==> (pre-fill blank; save empty to abort)"
  fi
fi

TMPFILE=$(mktemp /tmp/mandragora-commit-XXXXXX)
SAVED_FLAG="${TMPFILE}.saved"
trap 'rm -f "$TMPFILE" "$SAVED_FLAG"' EXIT

{
  echo "$MSG"
  echo ""
  echo "# Changes shown in split above. Save with message to apply, empty file or force-quit (QQ / :q!) to abort."
} > "$TMPFILE"

nvim -c "terminal git --no-pager diff --cached" \
     -c "belowright 3split $TMPFILE" \
     -c "setlocal winfixheight" \
     -c "autocmd VimResized * let w=winnr() | execute bufwinnr('$TMPFILE').'wincmd w' | resize 3 | execute w.'wincmd w'" \
     -c "autocmd BufWritePost <buffer> call writefile([], '$SAVED_FLAG') | qall"

if [ ! -f "$SAVED_FLAG" ]; then
  echo "==> Aborted (force-quit)."
  git restore --staged .
  exit 0
fi

MSG=$(grep -v '^#' "$TMPFILE" | sed '/^[[:space:]]*$/d')
if [ -z "$MSG" ]; then
  echo "==> Aborted."
  git restore --staged .
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
