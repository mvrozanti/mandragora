#!/usr/bin/env bash
set -eo pipefail
FLAKE="/etc/nixos/mandragora"

cd "$FLAKE"

LOCK_SESSION="switch-$$-$(date -u +%s)"
LOCK_RELEASED=0
release_lock() {
  if [ "$LOCK_RELEASED" -eq 0 ] && command -v mandragora-lock >/dev/null 2>&1; then
    mandragora-lock release "$LOCK_SESSION" >/dev/null 2>&1 || true
    LOCK_RELEASED=1
  fi
}
trap release_lock EXIT INT TERM

if command -v mandragora-lock >/dev/null 2>&1; then
  if ! mandragora-lock claim \
        --session "$LOCK_SESSION" \
        --phase commit \
        --paths "*" \
        --scope "nixos-rebuild switch" \
        --ttl 10min \
        --owner-pid "$$" \
        --agent "${MANDRAGORA_AGENT:-mandragora-switch}" >/dev/null; then
    echo "==> ABORTED: another agent holds an active lock on this repo." >&2
    echo "==> Run 'mandragora-lock list' to see who, then retry." >&2
    LOCK_RELEASED=1
    exit 1
  fi
fi

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

SKIP_EDIT=0
SKIP_COMMIT=0
ARGS=()
for arg in "$@"; do
  case "$arg" in
    !) SKIP_EDIT=1; SKIP_COMMIT=1 ;;
    -y|--no-edit) SKIP_EDIT=1 ;;
    *) ARGS+=("$arg") ;;
  esac
done

if [ "$SKIP_EDIT" -eq 0 ] && { [ ! -t 0 ] || [ ! -t 1 ]; }; then
  echo "==> No TTY detected; skipping editor."
  SKIP_EDIT=1
fi

if git diff --cached --quiet; then
  echo "==> No staged changes; skipping commit."
  SKIP_COMMIT=1
fi

MSG="${ARGS[*]}"
COMMIT_SKIPPED=0

if [ "$SKIP_COMMIT" -eq 1 ]; then
  COMMIT_SKIPPED=1
  git restore --staged . 2>/dev/null || true
elif [ "$SKIP_EDIT" -eq 1 ]; then
  if [ -z "$MSG" ] && command -v claude >/dev/null 2>&1; then
    echo "==> Generating commit message with claude (haiku)..."
    RECENT=$(git log --oneline -20)
    DIFF=$(git diff --cached)
    PROMPT_SYSTEM='You write a single git commit subject for a personal NixOS+Hyprland dotfiles repo. The user message contains the recent commit log (for style) followed by the staged diff. Mirror the log'\''s style exactly: if the log uses Conventional Commits prefixes, use one; if it doesn'\''t, don'\''t invent one. Output exactly ONE line, <=72 chars, imperative mood, no trailing period, no quotes, no preamble, no body. Nothing else.'
    PAYLOAD=$(printf '## RECENT LOG (style reference)\n%s\n\n## STAGED DIFF\n%s\n' "$RECENT" "$DIFF")
    if GENERATED=$(printf '%s' "$PAYLOAD" | timeout 60 claude -p --model claude-haiku-4-5 --no-session-persistence --system-prompt "$PROMPT_SYSTEM" "Write the commit subject for the staged diff." 2>/dev/null); then
      MSG=$(printf '%s' "$GENERATED" | sed -n '1p' | tr -d '\r')
    fi
  fi
  if [ -z "$MSG" ]; then
    echo "==> FAILED: no commit message and no AI generation available." >&2
    git restore --staged .
    exit 1
  fi
  git commit -m "$MSG"
else
  [ -n "$MSG" ] || MSG="switch"
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
