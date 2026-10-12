#!/usr/bin/env bash
set -eo pipefail
FLAKE="/etc/nixos/mandragora"

SRC="$FLAKE"
MODE="main"
FLAKE_REAL=$(realpath "$FLAKE" 2>/dev/null || echo "$FLAKE")
if git -C "$PWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  _top=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)
  _common=$(git -C "$PWD" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
  _mainwt=""
  [ -n "$_common" ] && _mainwt=$(realpath "$(dirname "$_common")" 2>/dev/null || dirname "$_common")
  if [ "$_mainwt" = "$FLAKE_REAL" ] && [ -n "$_top" ] && [ "$_top" != "$FLAKE_REAL" ] && [ "$_top" != "$FLAKE" ]; then
    MODE="worktree"
    SRC="$_top"
  fi
fi

cd "$SRC"

FORCE=0
SWEEP_ALL=0
VAULT_VERDICT=""
LOCK_WAIT=${MANDRAGORA_SWITCH_LOCK_WAIT_SECONDS:-1800}
PASSTHRU_ARGS=()
for arg in "$@"; do
  case "$arg" in
    -f|--force) FORCE=1 ;;
    --all) SWEEP_ALL=1 ;;
    --no-wait) LOCK_WAIT=0 ;;
    --vault=*) VAULT_VERDICT="${arg#--vault=}" ;;
    *) PASSTHRU_ARGS+=("$arg") ;;
  esac
done
set -- "${PASSTHRU_ARGS[@]}"
[ -n "$MANDRAGORA_SWITCH_FORCE" ] && FORCE=1
WAIT_DEADLINE=$(( $(date +%s) + LOCK_WAIT ))

LOCKDIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
mkdir -p "$LOCKDIR"
LOCKFILE="$LOCKDIR/mandragora-switch.lock"
exec 9>"$LOCKFILE"
if ! flock -n 9; then
  HOLDER=$(cat "${LOCKFILE}.pid" 2>/dev/null || echo "?")
  if [ "$LOCK_WAIT" -le 0 ]; then
    echo "==> ABORTED: another mandragora-switch is in progress (pid $HOLDER)." >&2
    exit 1
  fi
  echo "==> Waiting up to ${LOCK_WAIT}s for mandragora-switch pid $HOLDER ($(readlink "/proc/$HOLDER/cwd" 2>/dev/null || echo "?")) to finish..."
  if ! flock -w "$LOCK_WAIT" 9; then
    echo "==> ABORTED: another mandragora-switch is in progress (pid $(cat "${LOCKFILE}.pid" 2>/dev/null || echo "?")); gave up after ${LOCK_WAIT}s." >&2
    exit 1
  fi
  echo "==> Lock acquired."
fi
echo "$$" > "${LOCKFILE}.pid"

if [ "$MODE" = worktree ]; then
  echo "==> Worktree mode: building + committing only $SRC (branch $(git -C "$SRC" symbolic-ref --short HEAD 2>/dev/null || echo detached)). Other agents' work in the main tree is untouched."
else
  if [ "$SWEEP_ALL" = 1 ]; then
    echo "==> Main-tree mode (--all): sweeping every dirty path from $FLAKE."
  else
    echo "==> Main-tree mode: publish-only (builds + pushes; never commits working-tree state). Use a worktree to commit."
  fi
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

REBUILD_WAIT_SHOWN=0
while pgrep -f '[.]nixos-rebuild-wrapped' > /dev/null 2>&1; do
  if [ "$(date +%s)" -ge "$WAIT_DEADLINE" ]; then
    echo "==> ABORTED: nixos-rebuild is already running." >&2
    exit 1
  fi
  [ "$REBUILD_WAIT_SHOWN" -eq 1 ] || echo "==> Waiting for a nixos-rebuild started outside mandragora-switch to finish..."
  REBUILD_WAIT_SHOWN=1
  sleep 5
done

INTERACTIVE=1
if [ ! -t 0 ] || [ ! -t 1 ] || [ -n "$GEMINI_CLI" ]; then INTERACTIVE=0; fi
if [ "$INTERACTIVE" -eq 0 ] && [ -z "$MANDRAGORA_AGENT" ]; then export MANDRAGORA_AGENT=noninteractive-switch; fi
VAULT_TRAILER=()
[ -n "$VAULT_VERDICT" ] && VAULT_TRAILER=(--trailer "Vault: $VAULT_VERDICT")

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
  UNTRACKED=()
  while IFS= read -r -d '' p; do UNTRACKED+=("$p"); done < <(git -C "$FLAKE" ls-files --others --exclude-standard -z)

  SNAP_TRACKED=()
  SNAP_UNTRACKED=()
  if [ -n "$(git -C "$FLAKE" status --porcelain)" ]; then
    if [ "$SWEEP_ALL" -eq 1 ] && [ "$INTERACTIVE" -eq 1 ]; then
      while IFS= read -r -d '' p; do SNAP_TRACKED+=("$p"); done < <(git -C "$FLAKE" diff --name-only -z HEAD)
      SNAP_UNTRACKED=("${UNTRACKED[@]}")
      echo "==> --all (interactive): sweeping every dirty path in the main tree into this commit."
    elif [ "$SWEEP_ALL" -eq 1 ]; then
      echo "==> ABORTED: --all is refused without an interactive terminal." >&2
      echo "==> An agent must never sweep the shared main tree. Commit from a worktree:" >&2
      echo "==>   git worktree add .worktrees/<task> -b <branch> master && cd .worktrees/<task>" >&2
      exit 1
    else
      echo "==> ABORTED: the main tree is publish-only — mandragora-switch will not commit working-tree state from here." >&2
      echo "==> This is what prevents one agent's switch from sweeping another's WIP." >&2
      echo "==> Commit from a worktree (auto-scoped to your files):" >&2
      echo "==>   git worktree add .worktrees/<task> -b <branch> master && cd .worktrees/<task>" >&2
      echo "==> (interactive only) or 'mandragora-switch --all' to deliberately sweep everything here." >&2
      echo "==> Dirty paths:" >&2
      git -C "$FLAKE" status --short | sed 's/^/    /' >&2
      exit 1
    fi
  fi

  rm -rf "$WT"
  git -C "$FLAKE" worktree prune 2>/dev/null || true
  git -C "$FLAKE" worktree add --detach "$WT" "$MASTER_HEAD" >/dev/null

  for p in "${SNAP_TRACKED[@]}"; do
    if [ -e "$FLAKE/$p" ]; then
      mkdir -p "$WT/$(dirname "$p")"
      cp -a "$FLAKE/$p" "$WT/$p"
    else
      rm -f "$WT/$p"
    fi
  done
  for p in "${SNAP_UNTRACKED[@]}"; do
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
  git commit -m "$MSG" "${VAULT_TRAILER[@]}"
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
  git commit -m "$MSG" "${VAULT_TRAILER[@]}"
fi

warn_unbuilt() {
  local unbuilt
  unbuilt=$(git -C "$FLAKE" log --oneline "$1..$2" 2>/dev/null)
  [ -n "$unbuilt" ] || return 0
  echo "==> WARNING: these master commits are NOT in the generation this switch builds:" >&2
  printf '%s\n' "$unbuilt" | sed 's/^/    /' >&2
  echo "==> Re-run mandragora-switch afterwards (no changes needed) to activate them." >&2
}

if [ "$MODE" = worktree ]; then
  MASTER_HEAD=$(git -C "$FLAKE" rev-parse refs/heads/master)
  BUILD_BASE="$MASTER_HEAD"
  if git -C "$FLAKE" merge-base --is-ancestor "$MASTER_HEAD" refs/remotes/origin/master 2>/dev/null; then
    BUILD_BASE=$(git -C "$FLAKE" rev-parse refs/remotes/origin/master)
  fi
  if ! git -C "$WT" merge-base --is-ancestor "$BUILD_BASE" HEAD; then
    if [ -n "$(git -C "$WT" status --porcelain --untracked-files=no)" ]; then
      warn_unbuilt "$(git -C "$WT" merge-base "$BUILD_BASE" HEAD)" "$BUILD_BASE"
    else
      echo "==> Worktree is behind master; rebasing onto $(git -C "$FLAKE" rev-parse --short "$BUILD_BASE") so the build includes everything already landed..."
      if ! git -C "$WT" rebase "$BUILD_BASE"; then
        git -C "$WT" rebase --abort 2>/dev/null || true
        echo "==> ABORTED before building: your commit conflicts with master. Rebase $WT onto master by hand, then re-run." >&2
        exit 1
      fi
    fi
  fi
fi

if [ "$COMMIT_SKIPPED" -eq 1 ]; then
  if [ "$MODE" = worktree ]; then
    if ! git -C "$WT" merge-base --is-ancestor "$(git -C "$WT" rev-parse HEAD)" "$MASTER_HEAD" 2>/dev/null; then
      echo "==> Worktree already has commit(s) ahead of master; will promote them."
      COMMIT_SKIPPED=0
    fi
  elif [ "$(git -C "$FLAKE" rev-list --count origin/master..refs/heads/master 2>/dev/null || echo 0)" -gt 0 ]; then
    echo "==> master has unpushed commit(s); will push them."
    COMMIT_SKIPPED=0
  fi
fi

phase "commit prepared"

if [ "$MODE" = worktree ] && [ "$INTERACTIVE" -eq 0 ] && [ "$COMMIT_SKIPPED" -eq 0 ] && command -v mandragora-vault >/dev/null 2>&1; then
  if ! mandragora-vault gate --repo "$WT" "${BUILD_BASE:-$MASTER_HEAD}..HEAD"; then
    echo "==> ABORTED before building: every agent commit carries a Vault: verdict (AGENTS.md rule 22)." >&2
    exit 1
  fi
fi

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
echo "==> Building (capped in heavy.slice — a runaway build dies alone, not the session)..."
set +e
if command -v cage >/dev/null 2>&1; then CAP=(cage); else CAP=(); fi
"${CAP[@]}" sudo nixos-rebuild switch --flake "$WT#mandragora-desktop" 2>&1 | tee /tmp/nixos-rebuild.log | grep --line-buffered -E "^(error:|building|activating|warning:|Failed|systemctl|Done\.)"
RC=${PIPESTATUS[0]}
set -e
phase "nixos-rebuild switch (rc=$RC)"

ACTIVATED=0
if grep -q "^Done\. The new configuration is " /tmp/nixos-rebuild.log; then
  ACTIVATED=1
else
  NEW_TOPLEVEL=$(grep -oE "^switching to system configuration /nix/store/[^ ]+" /tmp/nixos-rebuild.log | tail -1 | awk '{print $NF}')
  if [ -n "$NEW_TOPLEVEL" ] && [ "$(readlink -f /run/current-system)" = "$(readlink -f "$NEW_TOPLEVEL")" ]; then
    ACTIVATED=1
  fi
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
    warn_unbuilt "$MASTER_HEAD" "$(git -C "$WT" rev-parse FETCH_HEAD)"
  fi

  if [ "$MODE" = worktree ]; then
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      if git -C "$FLAKE" diff --quiet "$MASTER_HEAD" -- "$f" 2>/dev/null; then
        if git -C "$FLAKE" cat-file -e "HEAD:$f" 2>/dev/null; then
          git -C "$FLAKE" checkout HEAD -- "$f" 2>/dev/null || true
        else
          git -C "$FLAKE" rm -q -f -- "$f" 2>/dev/null || true
        fi
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
        warn_unbuilt HEAD origin/master
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

if [ "$INTERACTIVE" -eq 0 ] && command -v mandragora-vault >/dev/null 2>&1; then
  echo "==> Vault: reviewing unpublished notes for demo.mvr.ac..."
  mandragora-vault publish || echo "==> WARNING: vault publish did not complete (above); the system switch itself is fine." >&2
  phase "vault publish"
fi

DEPLOY_DRIVER="$FLAKE/nix/hosts/mandragora-vps/deploy-stacks.sh"
if [ -f "$DEPLOY_DRIVER" ]; then
  echo "==> Served content: deploying what master changed since it was last deployed..."
  MANDRAGORA_SWITCH_LOCKED=1 bash "$DEPLOY_DRIVER" --sync || echo "==> WARNING: some served content did not deploy (above); the system switch itself is fine and the next switch retries." >&2
  phase "deploy served content"
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
