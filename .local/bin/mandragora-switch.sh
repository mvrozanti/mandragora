#!/usr/bin/env bash
set -eo pipefail
FLAKE="/etc/nixos/mandragora"

SRC="$FLAKE"
MODE="main"
if git -C "$PWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  _top=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)
  _common=$(git -C "$PWD" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
  _mainwt=""
  [ -n "$_common" ] && _mainwt=$(dirname "$_common")
  if [ "$_mainwt" = "$FLAKE" ] && [ -n "$_top" ] && [ "$_top" != "$FLAKE" ]; then
    MODE="worktree"
    SRC="$_top"
  fi
fi

cd "$SRC"

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

if [ "$MODE" = worktree ]; then
  echo "==> Worktree mode: building + committing only $SRC (branch $(git -C "$SRC" symbolic-ref --short HEAD 2>/dev/null || echo detached)). Other agents' work in the main tree is untouched."
else
  echo "==> Main-tree mode: snapshotting all dirty files from $FLAKE."
fi

WT="$LOCKDIR/mandragora-switch-wt"
TMPFILE=""
SAVED_FLAG=""
cleanup() {
  rm -f "${LOCKFILE}.pid"
  [ -n "$TMPFILE" ] && rm -f "$TMPFILE" "$SAVED_FLAG"
  if [ "$MODE" = main ] && [ -d "$WT" ]; then
    git -C "$FLAKE" worktree remove --force "$WT" 2>/dev/null || rm -rf "$WT"
    git -C "$FLAKE" worktree prune 2>/dev/null || true
  fi
}
trap cleanup EXIT

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

echo "==> Fetching origin..."
if ! git -C "$FLAKE" fetch origin; then
  echo "==> WARNING: git fetch failed. Proceeding without sync check." >&2
elif [ "$(git -C "$FLAKE" rev-list --count refs/heads/master..origin/master)" -gt 0 ]; then
  AHEAD_ORIGIN=$(git -C "$FLAKE" rev-list --count refs/heads/master..origin/master)
  if [ "$MODE" = main ]; then
    echo "==> Remote is ahead by $AHEAD_ORIGIN commit(s). Rebasing master..."
    if ! git -C "$FLAKE" pull --rebase --autostash origin master; then
      echo "==> FAILED: rebase conflict. Resolve manually then re-run." >&2
      exit 1
    fi
  else
    echo "==> Remote master ahead by $AHEAD_ORIGIN commit(s); will fold in during promote."
  fi
fi
phase "git fetch/rebase"

MASTER_HEAD=$(git -C "$FLAKE" rev-parse refs/heads/master)

if [ "$MODE" = worktree ]; then
  WT="$SRC"
else
  DIRTY_TRACKED=()
  while IFS= read -r -d '' p; do DIRTY_TRACKED+=("$p"); done < <(git -C "$FLAKE" diff --name-only -z HEAD)
  DIRTY_UNTRACKED=()
  while IFS= read -r -d '' p; do DIRTY_UNTRACKED+=("$p"); done < <(git -C "$FLAKE" ls-files --others --exclude-standard -z)

  rm -rf "$WT"
  git -C "$FLAKE" worktree prune 2>/dev/null || true
  git -C "$FLAKE" worktree add --detach "$WT" "$MASTER_HEAD" >/dev/null

  for p in "${DIRTY_TRACKED[@]}"; do
    if [ -e "$FLAKE/$p" ]; then
      mkdir -p "$WT/$(dirname "$p")"
      cp -a "$FLAKE/$p" "$WT/$p"
    else
      rm -f "$WT/$p"
    fi
  done
  for p in "${DIRTY_UNTRACKED[@]}"; do
    mkdir -p "$WT/$(dirname "$p")"
    cp -a "$FLAKE/$p" "$WT/$p"
  done
fi

cd "$WT"
export MANDRAGORA_REPO="$WT"

if command -v mandragora-audit >/dev/null 2>&1; then
  echo "==> Repo audit (pre-stage, worktree snapshot)..."
  if ! mandragora-audit --quiet --skip conventional-commits; then
    echo "==> ABORTED: repo audit failed. Fix the violations above and re-run." >&2
    exit 1
  fi
fi

git add -A

if ! git diff --cached --quiet; then
  echo "==> Staged for this switch (from frozen snapshot):"
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
echo "==> Pre-flight: evaluating other hosts..."
for host in mandragora-wsl; do
  if ! nix build "$WT#nixosConfigurations.$host.config.system.build.toplevel" --dry-run 2>/tmp/nix-eval-$host.log; then
    echo "==> ABORTED: $host eval failed. Fix before pushing:" >&2
    cat /tmp/nix-eval-$host.log >&2
    exit 1
  fi
  echo "==> [ok] $host"
done

echo ""
echo "==> Building..."
set +e
sudo nixos-rebuild switch --flake "$WT#mandragora-desktop" 2>&1 | tee /tmp/nixos-rebuild.log | grep --line-buffered -E "^(error:|building|activating|warning:|Failed|systemctl|Done\.)"
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
  exit "$RC"
fi

if [ "$COMMIT_SKIPPED" -eq 0 ]; then
  NEW_COMMIT=$(git -C "$WT" rev-parse HEAD)

  PROMOTED=0
  if git -C "$WT" merge-base --is-ancestor "$MASTER_HEAD" "$NEW_COMMIT" 2>/dev/null \
     && git -C "$FLAKE" update-ref -m "mandragora-switch: promote $NEW_COMMIT" \
          refs/heads/master "$NEW_COMMIT" "$MASTER_HEAD" 2>/dev/null; then
    PROMOTED=1
  fi
  if [ "$PROMOTED" -eq 0 ]; then
    echo "==> Master moved or commit not on top of it; rebasing onto current master..."
    if ! git -C "$WT" fetch "$FLAKE" master >/dev/null 2>&1 \
      || ! git -C "$WT" rebase FETCH_HEAD; then
      echo "==> FAILED: rebase conflict between your commit and concurrent master changes. Resolve in $WT, then manually update master." >&2
      exit 1
    fi
    NEW_COMMIT=$(git -C "$WT" rev-parse HEAD)
    git -C "$FLAKE" update-ref refs/heads/master "$NEW_COMMIT"
  fi

  if [ "$MODE" = worktree ]; then
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      if git -C "$FLAKE" diff --quiet "$MASTER_HEAD" -- "$f" 2>/dev/null; then
        git -C "$FLAKE" checkout HEAD -- "$f" 2>/dev/null || true
      else
        echo "==> NOTE: $f also changed in the main tree; left as-is there (resolve manually)." >&2
      fi
    done < <(git -C "$FLAKE" diff --name-only HEAD)
  fi

  cd "$FLAKE"
  phase "promote to master"

  MAX_PUSH_ATTEMPTS=${MANDRAGORA_SWITCH_PUSH_ATTEMPTS:-3}
  attempt=0
  while true; do
    attempt=$((attempt + 1))
    if git fetch origin 2>/dev/null; then
      AHEAD_REMOTE=$(git rev-list --count HEAD..origin/master 2>/dev/null || echo 0)
      if [ "$AHEAD_REMOTE" -gt 0 ]; then
        echo "==> Origin moved by $AHEAD_REMOTE commit(s) during build; rebasing local commit on top..."
        if ! git pull --rebase --autostash origin master; then
          echo "==> FAILED: rebase conflict between local commit and origin updates. Resolve manually then push." >&2
          exit 1
        fi
      fi
    fi
    echo "==> Pushing (attempt $attempt/$MAX_PUSH_ATTEMPTS)..."
    if git push; then
      phase "git push"
      break
    fi
    if [ "$attempt" -ge "$MAX_PUSH_ATTEMPTS" ]; then
      echo "==> FAILED: push rejected after $attempt attempts. Your local commit is on HEAD but NOT on origin." >&2
      echo "==> Run: git pull --rebase && git push" >&2
      exit 1
    fi
    echo "==> Push rejected — re-fetching and retrying..." >&2
  done
fi

if [ "$RC" -eq 0 ] || [ "$ACTIVATED" -eq 1 ]; then
  WINDOW_SECONDS=${MANDRAGORA_GEN_WINDOW_SECONDS:-7200}
  if [ "$WINDOW_SECONDS" -gt 0 ]; then
    CURRENT_LINK=/nix/var/nix/profiles/system
    CURRENT_NUM=$(basename "$(readlink "$CURRENT_LINK")" | sed -n 's/^system-\([0-9]\+\)-link$/\1/p')
    if [ -n "$CURRENT_NUM" ]; then
      BOOTED_PATH=$(readlink -f /run/booted-system)
      ENTRIES=()
      for link in /nix/var/nix/profiles/system-*-link; do
        num=$(basename "$link" | sed -n 's/^system-\([0-9]\+\)-link$/\1/p')
        [ -z "$num" ] && continue
        mtime=$(stat -c %Y "$link")
        protected=0
        [ "$num" = "$CURRENT_NUM" ] && protected=1
        [ "$(readlink -f "$link")" = "$BOOTED_PATH" ] && protected=1
        ENTRIES+=("$mtime $num $protected")
      done
      SORTED=$(printf '%s\n' "${ENTRIES[@]}" | sort -rn)
      LAST_KEPT_MTIME=""
      COALESCE=()
      while IFS=' ' read -r mtime num protected; do
        [ -z "$num" ] && continue
        if [ "$protected" = "1" ]; then
          LAST_KEPT_MTIME="$mtime"
          continue
        fi
        if [ -n "$LAST_KEPT_MTIME" ] && [ $((LAST_KEPT_MTIME - mtime)) -lt "$WINDOW_SECONDS" ]; then
          COALESCE+=("$num")
        else
          LAST_KEPT_MTIME="$mtime"
        fi
      done <<< "$SORTED"
      if [ "${#COALESCE[@]}" -gt 0 ]; then
        echo "==> Coalescing ${#COALESCE[@]} generation(s) closer than ${WINDOW_SECONDS}s to a kept neighbor: ${COALESCE[*]}"
        PRUNED_LOG=$(sudo nix-env -p /nix/var/nix/profiles/system --delete-generations "${COALESCE[@]}" 2>&1)
        if [ $? -eq 0 ]; then
          if echo "$PRUNED_LOG" | grep -qEi "removing (generation|profile version)"; then
            sudo /run/current-system/bin/switch-to-configuration boot >/dev/null 2>&1 || \
              echo "==> WARNING: bootloader refresh after coalesce failed; entries may be stale until next switch." >&2
          else
            echo "==> No generations were actually pruned."
          fi
        else
          echo "==> WARNING: generation coalesce failed: $PRUNED_LOG" >&2
        fi
        phase "coalesce generations"
      fi
    fi
  fi

  GC_DAYS=${MANDRAGORA_GC_DAYS:-7}
  if [ "$GC_DAYS" -gt 0 ]; then
    echo "==> Pruning system generations older than ${GC_DAYS}d..."
    sudo /run/current-system/sw/bin/nix-env -p /nix/var/nix/profiles/system --delete-generations "${GC_DAYS}d" >/dev/null 2>&1 || \
      echo "==> WARNING: generation prune (${GC_DAYS}d) failed." >&2
    echo "==> nix-store --gc..."
    nix-store --gc >/dev/null 2>&1 || echo "==> WARNING: nix-store --gc failed." >&2
    phase "gc ${GC_DAYS}d"
  fi
fi

phase "done"
exit "$RC"
