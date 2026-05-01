#!/usr/bin/env bash
set -eo pipefail
FLAKE="/etc/nixos/mandragora"

cd "$FLAKE"

LOCKDIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
mkdir -p "$LOCKDIR"
LOCKFILE="$LOCKDIR/mandragora-switch.lock"
exec 9>"$LOCKFILE"
if ! flock -n 9; then
  HOLDER=$(cat "${LOCKFILE}.pid" 2>/dev/null || echo "?")
  echo "==> ABORTED: another mandragora-switch is in progress (pid $HOLDER)." >&2
  echo "==> If that is stale, remove $LOCKFILE and ${LOCKFILE}.pid." >&2
  exit 1
fi
echo "$$" > "${LOCKFILE}.pid"
trap 'rm -f "${LOCKFILE}.pid"' EXIT

TOTAL_START=$(date +%s)
PHASE_START=$TOTAL_START
phase() {
  local now elapsed_total elapsed_phase
  now=$(date +%s)
  elapsed_total=$((now - TOTAL_START))
  elapsed_phase=$((now - PHASE_START))
  printf '==> [+%3ds total, %3ds phase] %s\n' "$elapsed_total" "$elapsed_phase" "$*"
  PHASE_START=$now
}

if pgrep -x nixos-rebuild > /dev/null 2>&1; then
  echo "==> ABORTED: nixos-rebuild is already running." >&2
  exit 1
fi

FORCE=0
PASSTHRU_ARGS=()
for arg in "$@"; do
  case "$arg" in
    -f|--force) FORCE=1 ;;
    *) PASSTHRU_ARGS+=("$arg") ;;
  esac
done
set -- "${PASSTHRU_ARGS[@]}"
[ -n "$MANDRAGORA_SWITCH_FORCE" ] && FORCE=1

STABILITY_WAIT=${MANDRAGORA_SWITCH_STABILITY_SECONDS:-2}
if [ "$FORCE" -eq 0 ] && [ "$STABILITY_WAIT" -gt 0 ]; then
  SNAP_BEFORE=$(git status --porcelain=v1 -uall)
  SNAP_BEFORE_MTIMES=""
  while IFS= read -r line; do
    path="${line:3}"
    [ -z "$path" ] && continue
    case "$line" in
      'R '*|R*) path="${path##* -> }" ;;
    esac
    [ -e "$path" ] || continue
    m=$(stat -c %Y -- "$path" 2>/dev/null) || continue
    SNAP_BEFORE_MTIMES+="$m $path"$'\n'
  done <<< "$SNAP_BEFORE"

  sleep "$STABILITY_WAIT"

  SNAP_AFTER=$(git status --porcelain=v1 -uall)
  SNAP_AFTER_MTIMES=""
  while IFS= read -r line; do
    path="${line:3}"
    [ -z "$path" ] && continue
    case "$line" in
      'R '*|R*) path="${path##* -> }" ;;
    esac
    [ -e "$path" ] || continue
    m=$(stat -c %Y -- "$path" 2>/dev/null) || continue
    SNAP_AFTER_MTIMES+="$m $path"$'\n'
  done <<< "$SNAP_AFTER"

  if [ "$SNAP_BEFORE" != "$SNAP_AFTER" ] || [ "$SNAP_BEFORE_MTIMES" != "$SNAP_AFTER_MTIMES" ]; then
    echo "==> ABORTED: working tree changed during ${STABILITY_WAIT}s stability window — another editor is active:" >&2
    diff <(printf '%s' "$SNAP_BEFORE") <(printf '%s' "$SNAP_AFTER") | sed 's/^/    /' >&2
    diff <(printf '%s' "$SNAP_BEFORE_MTIMES") <(printf '%s' "$SNAP_AFTER_MTIMES") | sed 's/^/    /' >&2
    echo "==> Wait for the editor to finish, or override with: --force / MANDRAGORA_SWITCH_FORCE=1." >&2
    echo "==> Tune via MANDRAGORA_SWITCH_STABILITY_SECONDS (set 0 to disable)." >&2
    exit 1
  fi
fi

if command -v mandragora-audit >/dev/null 2>&1; then
  echo "==> Repo audit (pre-stage)..."
  if ! mandragora-audit --quiet --skip conventional-commits; then
    echo "==> ABORTED: repo audit failed. Fix the violations above and re-run." >&2
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
phase "git fetch/rebase"

git add -A

if ! git diff --cached --quiet; then
  echo "==> Staged for this switch:"
  git diff --cached --stat | sed 's/^/    /'
fi

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

if [ "$SKIP_EDIT" -eq 0 ]; then
  if [ -n "$GEMINI_CLI" ]; then
    echo "==> Gemini CLI detected; skipping editor."
    SKIP_EDIT=1
  elif { [ ! -t 0 ] || [ ! -t 1 ]; }; then
    echo "==> No TTY detected; skipping editor."
    SKIP_EDIT=1
  fi
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
  if [ -z "$MSG" ] && [ -n "$GEMINI_CLI" ]; then
    echo "==> Generating commit message with gemini..."
    RECENT=$(git log --oneline -20)
    DIFF=$(git diff --cached)
    PROMPT_SYSTEM="You write a single git commit subject for a personal NixOS+Hyprland dotfiles repo. The user message contains the recent commit log (for style) followed by the staged diff. Mirror the log style exactly: if the log uses Conventional Commits prefixes, use one; if it doesn t, don t invent one. Output exactly ONE line, <=72 chars, imperative mood, no trailing period, no quotes, no preamble, no body. Nothing else."
    PAYLOAD=$(printf "## RECENT LOG (style reference)\n%s\n\n## STAGED DIFF\n%s\n" "$RECENT" "$DIFF")
    if GENERATED=$(echo "$PAYLOAD" | timeout 60 gemini --prompt "$PROMPT_SYSTEM" 2>/dev/null); then
       MSG=$(echo "$GENERATED" | sed -n "1p" | tr -d "\r")
    fi
  fi
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

phase "commit prepared"

echo ""
echo "==> Building..."
set +e
sudo nixos-rebuild switch --flake "$FLAKE#mandragora-desktop" 2>&1 | tee /tmp/nixos-rebuild.log | grep --line-buffered -E "^(error:|building|activating|warning:|Failed|systemctl|Done\.)"
RC=${PIPESTATUS[0]}
set -e
phase "nixos-rebuild switch (rc=$RC)"

ACTIVATED=0
if grep -q "^Done\. The new configuration is " /tmp/nixos-rebuild.log; then
  ACTIVATED=1
fi

if [ "$RC" -eq 0 ]; then
  echo ""
  echo "==> Switch successful."
elif [ "$ACTIVATED" -eq 1 ]; then
  echo ""
  echo "==> Switch ACTIVATED (new generation is live), but rebuild exited rc=$RC." >&2
  echo "==> Some unit(s) failed during start. Commit kept; review failures:" >&2
  grep -E "(failed to start|Failed to start|the following units failed|Job .* failed|systemctl status)" /tmp/nixos-rebuild.log | tail -20 >&2 || true
else
  echo ""
  echo "==> FAILED before activation completed (rc=$RC). Full log: /tmp/nixos-rebuild.log" >&2
  if [ "$COMMIT_SKIPPED" -eq 0 ]; then
    git reset HEAD~1
  fi
  exit "$RC"
fi

if [ "$COMMIT_SKIPPED" -eq 0 ]; then
  echo "==> Pushing..."
  if ! git push; then
    echo "==> FAILED: push was rejected. Your local commit is NOT on origin." >&2
    echo "==> Run: git pull --rebase && git push" >&2
    exit 1
  fi
  phase "git push"
fi

phase "done"
exit "$RC"
