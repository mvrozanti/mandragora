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

usage() {
  cat <<'USAGE'
usage: mandragora-switch [flags] [commit message]

Commits what is staged in this tree (a worktree) or publishes master (the main
tree), rebuilds and activates the desktop, pushes, deploys the served content
and publishes the vault.

  -h, --help           print this and exit
  -f, --force          skip the stability window that aborts while another editor is active
      --all            main tree, interactive only: sweep every dirty path into the commit
      --no-wait        abort at once if another switch holds the lock, instead of waiting
      --vault=VERDICT  the Vault: trailer of an agent commit: a note path, or none (<why>)
  -y, --no-edit        skip the commit-message editor
  !                    build and switch without committing
USAGE
}

FORCE=0
SWEEP_ALL=0
VAULT_VERDICT=""
LOCK_WAIT=${MANDRAGORA_SWITCH_LOCK_WAIT_SECONDS:-1800}
PASSTHRU_ARGS=()
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    -f|--force) FORCE=1 ;;
    --all) SWEEP_ALL=1 ;;
    --no-wait) LOCK_WAIT=0 ;;
    --vault=*) VAULT_VERDICT="${arg#--vault=}" ;;
    -y|--no-edit|!) PASSTHRU_ARGS+=("$arg") ;;
    -*) echo "==> ABORTED: unknown flag $arg (mandragora-switch --help lists them)." >&2; exit 2 ;;
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
FETCH_PID=""
FETCH_LOG=""
MSG_PID=""
MSG_FILE=""
AUDIT_STAMP=""
WSL_PID=""
WSL_LOG=""
PUBLISH_PID=""
PUBLISH_LOG=""
cleanup() {
  rm -f "${LOCKFILE}.pid"
  [ -n "$TMPFILE" ] && rm -f "$TMPFILE" "$SAVED_FLAG"
  [ -n "$WSL_PID" ] && kill "$WSL_PID" 2>/dev/null
  rm -f ${FETCH_LOG:+"$FETCH_LOG"} ${MSG_FILE:+"$MSG_FILE"} ${AUDIT_STAMP:+"$AUDIT_STAMP"} ${WSL_LOG:+"$WSL_LOG"} ${PUBLISH_LOG:+"$PUBLISH_LOG"}
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

if [ "$MODE" = worktree ]; then
  FETCH_LOG=$(mktemp "$LOCKDIR/mandragora-switch-fetch.XXXXXX")
  git -C "$FLAKE" fetch origin >"$FETCH_LOG" 2>&1 &
  FETCH_PID=$!
fi

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

FETCH_OK=1
if [ -n "$FETCH_PID" ]; then
  echo "==> Fetching origin (started in the background)..."
  wait "$FETCH_PID" || FETCH_OK=0
  cat "$FETCH_LOG"
else
  echo "==> Fetching origin..."
  git -C "$FLAKE" fetch origin || FETCH_OK=0
fi
if [ "$FETCH_OK" -eq 0 ]; then
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

generate_commit_message() {
  local recent diff payload generated prompt
  recent=$(git log --oneline -20)
  diff=$(git diff --cached)
  if [ -n "$GEMINI_CLI" ]; then
    echo "==> Generating commit message with gemini..." >&2
    prompt="You write a single git commit subject for a personal NixOS+Hyprland dotfiles repo. The user message contains the recent commit log (for style) followed by the staged diff. Mirror the log style exactly: if the log uses Conventional Commits prefixes, use one; if it doesn t, don t invent one. Output exactly ONE line, <=72 chars, imperative mood, no trailing period, no quotes, no preamble, no body. Nothing else."
    payload=$(printf "## RECENT LOG (style reference)\n%s\n\n## STAGED DIFF\n%s\n" "$recent" "$diff")
    if generated=$(echo "$payload" | timeout 60 gemini --prompt "$prompt" 2>/dev/null); then
      generated=$(echo "$generated" | sed -n "1p" | tr -d "\r")
      [ -n "$generated" ] && { printf '%s\n' "$generated"; return 0; }
    fi
  fi
  command -v claude >/dev/null 2>&1 || return 0
  echo "==> Generating commit message with claude (haiku)..." >&2
  prompt='You write a single git commit subject for a personal NixOS+Hyprland dotfiles repo. The user message contains the recent commit log (for style) followed by the staged diff. Mirror the log'\''s style exactly: if the log uses Conventional Commits prefixes, use one; if it doesn'\''t, don'\''t invent one. Output exactly ONE line, <=72 chars, imperative mood, no trailing period, no quotes, no preamble, no body. Nothing else.'
  payload=$(printf '## RECENT LOG (style reference)\n%s\n\n## STAGED DIFF\n%s\n' "$recent" "$diff")
  if generated=$(printf '%s' "$payload" | timeout 60 claude -p --model claude-haiku-4-5 --no-session-persistence --system-prompt "$prompt" "Write the commit subject for the staged diff." 2>/dev/null); then
    printf '%s' "$generated" | sed -n '1p' | tr -d '\r'
  fi
}

PRE_STAGE_INDEX=$(git write-tree 2>/dev/null || true)
git add -A
AUDITED_TREE=$(git write-tree)

if git diff --cached --quiet; then
  echo "==> No staged changes; skipping commit."
  SKIP_COMMIT=1
fi

MSG="${ARGS[*]}"
if [ "$SKIP_COMMIT" -eq 0 ] && [ "$SKIP_EDIT" -eq 1 ] && [ -z "$MSG" ]; then
  MSG_FILE=$(mktemp "$LOCKDIR/mandragora-switch-msg.XXXXXX")
  generate_commit_message >"$MSG_FILE" &
  MSG_PID=$!
fi

if command -v mandragora-audit >/dev/null 2>&1; then
  echo "==> Repo audit (staged snapshot)..."
  if ! mandragora-audit --quiet --skip conventional-commits; then
    if [ -n "$MSG_PID" ]; then
      pkill -TERM -P "$MSG_PID" 2>/dev/null || true
      kill "$MSG_PID" 2>/dev/null || true
    fi
    [ -n "$PRE_STAGE_INDEX" ] && git read-tree "$PRE_STAGE_INDEX"
    echo "==> ABORTED: repo audit failed. Fix the violations above and re-run." >&2
    exit 1
  fi
  AUDIT_STAMP=$(git rev-parse --path-format=absolute --git-path mandragora-audited-tree)
  printf '%s\n' "$AUDITED_TREE" >"$AUDIT_STAMP"
fi

if ! git diff --cached --quiet; then
  echo "==> Staged for this switch (from frozen snapshot):"
  git diff --cached --stat | sed 's/^/    /'
fi

COMMIT_SKIPPED=0

if [ "$SKIP_COMMIT" -eq 1 ]; then
  COMMIT_SKIPPED=1
  git restore --staged . 2>/dev/null || true
elif [ "$SKIP_EDIT" -eq 1 ]; then
  if [ -z "$MSG" ] && [ -n "$MSG_PID" ]; then
    wait "$MSG_PID" || true
    MSG=$(sed -n '1p' "$MSG_FILE" | tr -d '\r')
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
  RUNNING_REV=$(cat /run/current-system/git-revision 2>/dev/null || true)
  case "$RUNNING_REV" in "" | dirty | *-dirty) RUNNING_REV="" ;; esac
  if [ -n "$RUNNING_REV" ] && git -C "$WT" cat-file -e "$RUNNING_REV^{commit}" 2>/dev/null \
     && [ -n "$(git -C "$WT" cherry "$BUILD_BASE" "$RUNNING_REV" 2>/dev/null | grep '^+')" ]; then
    echo "==> Running generation has commit(s) not yet on master; folding them in so they land instead of being dropped:"
    git -C "$WT" cherry "$BUILD_BASE" "$RUNNING_REV" 2>/dev/null | sed -n 's/^+ //p' \
      | while IFS= read -r c; do git -C "$WT" log --oneline -1 "$c" 2>/dev/null | sed 's/^/      /'; done
    BUILD_BASE="$RUNNING_REV"
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
EVAL_REF="$WT"
if [ -z "$(git -C "$WT" status --porcelain --untracked-files=no)" ]; then
  EVAL_REF="git+file://$WT?rev=$(git -C "$WT" rev-parse HEAD)"
fi
WSL_LOG=$(mktemp "$LOCKDIR/mandragora-switch-wsl.XXXXXX")
nix build --dry-run "$EVAL_REF#nixosConfigurations.mandragora-wsl.config.system.build.toplevel" >"$WSL_LOG" 2>&1 &
WSL_PID=$!
echo "==> Pre-flight: mandragora-wsl evaluates in the background; a failure still blocks the push."

if [ "$INTERACTIVE" -eq 0 ] && command -v mandragora-vault >/dev/null 2>&1; then
  PUBLISH_LOG=$(mktemp "$LOCKDIR/mandragora-switch-publish.XXXXXX")
  mandragora-vault publish >"$PUBLISH_LOG" 2>&1 &
  PUBLISH_PID=$!
  echo "==> Vault: reviewing unpublished notes for demo.mvr.ac in the background..."
fi

echo ""
echo "==> Building (the guard evaluates the desktop once, as $(id -un), then root activates; capped in heavy.slice)..."
set +e
if command -v cage >/dev/null 2>&1; then CAP=(cage); else CAP=(); fi
"${CAP[@]}" sudo nixos-rebuild switch --flake "$WT#mandragora-desktop" 2>&1 | tee /tmp/nixos-rebuild.log | grep --line-buffered -E "^(error:|building|activating|warning:|Failed|systemctl|Done\.|nixos-rebuild guard)"
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

if wait "$WSL_PID"; then
  echo "==> [ok] mandragora-wsl evaluates"
else
  echo "==> ABORTED before promoting: mandragora-wsl failed to evaluate. The desktop already runs this commit; fix the WSL eval and re-run mandragora-switch, which folds the running commit in:" >&2
  cat "$WSL_LOG" >&2
  exit 1
fi
WSL_PID=""

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
    if [ "$attempt" -gt 1 ] && git fetch origin 2>/dev/null; then
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

if [ -n "$PUBLISH_PID" ]; then
  echo "==> Vault publish (ran during the build):"
  wait "$PUBLISH_PID" || echo "==> WARNING: vault publish did not complete (below); the system switch itself is fine." >&2
  sed 's/^/    /' "$PUBLISH_LOG"
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
        PRUNED_LOG=$(sudo mandragora-gen-prune "${COALESCE[@]}" 2>&1)
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
    echo "==> Pruning system generations older than ${GC_DAYS}d (the store itself is collected by the weekly nix.gc timer and by min-free)..."
    sudo mandragora-gen-prune "${GC_DAYS}d" >/dev/null 2>&1 || \
      echo "==> WARNING: generation prune (${GC_DAYS}d) failed." >&2
    phase "prune ${GC_DAYS}d"
  fi
fi

phase "done"
exit "$RC"
