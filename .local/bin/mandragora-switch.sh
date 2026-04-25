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
        --ttl 30min \
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

if git diff --cached --quiet; then
  echo "==> No uncommitted changes."
fi

SKIP_EDIT=0
ARGS=()
for arg in "$@"; do
  case "$arg" in
    -y|--no-edit) SKIP_EDIT=1 ;;
    *) ARGS+=("$arg") ;;
  esac
done

if [ "${#ARGS[@]}" -eq 1 ] && [ "${ARGS[0]}" = "!" ]; then
  SKIP_EDIT=1
  MSG="!"
elif [[ "${ARGS[*]}" == *"!"* ]]; then
  SKIP_EDIT=1
  ARGS=("${ARGS[@]/!/}")
  MSG="${ARGS[*]:-switch}"
else
  MSG="${ARGS[*]:-switch}"
fi

if [ "$SKIP_EDIT" -eq 0 ]; then
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
