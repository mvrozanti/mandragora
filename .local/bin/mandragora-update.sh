#!/usr/bin/env bash
set -eo pipefail

FLAKE="${MANDRAGORA_REPO:-/etc/nixos/mandragora}"
HOST="${MANDRAGORA_HOST:-mandragora-desktop}"
BRANCH="nixos-unstable"
SETTLE_DAYS=14
HEAD_ONLY=0
DRY=0
AUTO=0
ACTION="switch"
RESUME_WT=""
KEEP_WT=0
STATUSDIR="/persistent/mandragora-update"

usage() {
  cat <<'EOF'
mandragora-update — update flake.lock only as far as the binary cache allows.

Runs flake update in a throwaway worktree, dry-runs the desktop toplevel to
split build-from-source vs fetch-from-cache, and refuses to switch onto a lock
that would compile a heavy uncached package (the Rule-19 oomd trap). If HEAD is
not cache-warm it settles back to the newest nixos-unstable rev that is
download-only, then commits the lock bump, switches, promotes to master, pushes.

Usage: mandragora-update [flags]
  --settle-days N   oldest rev settle-back may reach (default 14)
  --head-only       never settle back; abort if HEAD is not cache-warm
  --dry             gate + report only; do not commit or switch
  --auto            unattended: switch only if a warm rev is found, else record
                    a pending notice; no editor, no prompts
  --boot            stage with `nixos-rebuild boot` instead of live `switch`
  --resume DIR      resume in an existing worktree after a manual eval fix
  -h, --help        this text
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --settle-days) SETTLE_DAYS="$2"; shift 2 ;;
    --settle-days=*) SETTLE_DAYS="${1#*=}"; shift ;;
    --head-only) HEAD_ONLY=1; shift ;;
    --dry) DRY=1; shift ;;
    --auto) AUTO=1; shift ;;
    --boot) ACTION="boot"; shift ;;
    --resume) RESUME_WT="$2"; shift 2 ;;
    --resume=*) RESUME_WT="${1#*=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
  export GIT_AUTHOR_NAME="mvrozanti" GIT_AUTHOR_EMAIL="mvrozanti@gmail.com"
  export GIT_COMMITTER_NAME="mvrozanti" GIT_COMMITTER_EMAIL="mvrozanti@gmail.com"
  git config --global --get-all safe.directory 2>/dev/null | grep -qxF "$FLAKE" || \
    git config --global --add safe.directory "$FLAKE"
else
  SUDO="sudo"
fi

RUNBASE="${XDG_RUNTIME_DIR:-}"
if [ -z "$RUNBASE" ] || [ ! -w "$RUNBASE" ]; then RUNBASE="/tmp"; fi
LOCKFILE="$RUNBASE/mandragora-switch.lock"
exec 9>"$LOCKFILE"
if ! flock -n 9; then
  echo "==> ABORTED: a mandragora-switch/update already holds $LOCKFILE." >&2
  exit 1
fi
echo "$$" > "${LOCKFILE}.pid"

if pgrep -x nixos-rebuild >/dev/null 2>&1; then
  echo "==> ABORTED: nixos-rebuild is already running." >&2
  exit 1
fi

WT="$RUNBASE/mandragora-update-wt"
cleanup() {
  rm -f "${LOCKFILE}.pid"
  if [ -z "$RESUME_WT" ] && [ "$KEEP_WT" != 1 ] && [ -d "$WT" ]; then
    git -C "$FLAKE" worktree remove --force "$WT" 2>/dev/null || rm -rf "$WT"
    git -C "$FLAKE" worktree prune 2>/dev/null || true
  fi
}
trap cleanup EXIT

phase() { printf '==> %s\n' "$*"; }

notify_pending() {
  local reason="$1"
  mkdir -p "$STATUSDIR"
  { echo "pending since: $(date -Is)"; echo "reason: $reason"; } > "$STATUSDIR/pending.txt"
  echo "==> PENDING: $reason (recorded at $STATUSDIR/pending.txt)" >&2
}

rev_as_of_days() {
  local days="$1" cutoff body
  cutoff=$(date -u -d "-${days} days" +%Y-%m-%dT%H:%M:%SZ)
  body=$(curl -fsSL "https://api.github.com/repos/NixOS/nixpkgs/commits?sha=${BRANCH}&until=${cutoff}&per_page=1" 2>/dev/null) || return 0
  printf '%s' "$body" | grep -oE '"sha": ?"[0-9a-f]{40}"' | head -n1 | grep -oE '[0-9a-f]{40}' || true
}

ALLOWLIST="$WT/.local/share/mandragora-update/expected-local-builds.txt"
TRIVIAL='\.conf\.drv$|\.conf$|X-Restart-Triggers|X-Reload-Triggers|abstractions-|\.patch\.drv$|-fmt(-|\.)|texlive|^hm_|-archive\.tar|-source\.drv$|tmpfiles|^unit-|\.(service|mount|target|timer|socket|slice)\.drv$|^etc-|^[0-9]+-'
HEAVY='libreoffice|^wine|chromium|webkit|qtwebengine|electron|cuda_(nvcc|cudart|cccl|nvml|libcublas)|^llvm|llvm-|rustc|^gcc-[0-9]|^glibc-2|linux-[0-9].*-modules|nodejs-[0-9]|ollama|open-webui-frontend|firefox-[0-9]|thunderbird|blender|tensorflow|^torch|^ghc-'

heavy_builds() {
  local logf="$1" built
  built=$(sed -n '/ will be built:/,/ will be fetched/{/^  \/nix\/store\//p}' "$logf" \
            | sed -E 's/^ *\/nix\/store\/[a-z0-9]+-//; s/\.drv$//')
  printf '%s\n' "$built" \
    | grep -Ev "$TRIVIAL" 2>/dev/null \
    | grep -Ei "$HEAVY" 2>/dev/null \
    | { if [ -f "$ALLOWLIST" ]; then grep -Evf "$ALLOWLIST"; else cat; fi; } \
    | sort -u || true
}

GATELOG=$(mktemp /tmp/mandragora-update-gate-XXXXXX)
gate() {
  if nix build "${WT}#nixosConfigurations.${HOST}.config.system.build.toplevel" \
       --dry-run >"$GATELOG" 2>&1; then
    return 0
  fi
  return 1
}

MASTER_HEAD=$(git -C "$FLAKE" rev-parse refs/heads/master)

if [ -n "$RESUME_WT" ]; then
  WT="$RESUME_WT"
  KEEP_WT=1
  cd "$WT"
  phase "Resuming in $WT (skipping flake update)."
else
  phase "Fetching origin..."
  git -C "$FLAKE" fetch origin >/dev/null 2>&1 || echo "==> WARNING: fetch failed; continuing." >&2
  if [ "$(git -C "$FLAKE" rev-list --count refs/heads/master..origin/master 2>/dev/null || echo 0)" -gt 0 ]; then
    phase "Rebasing master onto origin..."
    git -C "$FLAKE" pull --rebase --autostash origin master || {
      echo "==> FAILED: master rebase conflict. Resolve then re-run." >&2; exit 1; }
    MASTER_HEAD=$(git -C "$FLAKE" rev-parse refs/heads/master)
  fi

  rm -rf "$WT"
  git -C "$FLAKE" worktree prune 2>/dev/null || true
  git -C "$FLAKE" worktree add --detach "$WT" "$MASTER_HEAD" >/dev/null
  cd "$WT"

  phase "flake update (all inputs) → channel HEAD..."
  nix flake update >/dev/null 2>&1
fi

phase "Gate: eval + build-vs-fetch on HEAD..."
if ! gate; then
  if grep -qiE "has been removed|refusing to evaluate|marked as insecure|cannot coerce|error: attribute .* missing" "$GATELOG"; then
    KEEP_WT=1
    echo "" >&2
    echo "==> EVAL BROKE on the new lock — a package was removed/renamed/marked insecure:" >&2
    grep -iE "has been removed|refusing to evaluate|marked as insecure|error:" "$GATELOG" | head -8 | sed 's/^/    /' >&2
    echo "" >&2
    echo "==> Fix the reference in $WT, then resume:" >&2
    echo "==>   mandragora-update --resume $WT ${AUTO:+--auto}" >&2
    if [ "$AUTO" -eq 1 ]; then notify_pending "eval breakage on new lock (manual fix needed)"; fi
    exit 2
  fi
  echo "==> FAILED: dry-run errored (not a known eval-adaptation):" >&2
  tail -20 "$GATELOG" >&2
  exit 1
fi

CHOSEN_DAYS=0
BLOCKERS=$(heavy_builds "$GATELOG")
if [ -n "$BLOCKERS" ]; then
  echo "==> HEAD is NOT cache-warm — would build from source:" >&2
  printf '%s\n' "$BLOCKERS" | sed 's/^/      /' >&2
  if [ "$HEAD_ONLY" -eq 1 ]; then
    [ "$AUTO" -eq 1 ] && notify_pending "HEAD not cache-warm; --head-only set"
    echo "==> --head-only: not settling back. Try again in a day or two." >&2
    exit 3
  fi
  phase "Settling back to the newest cache-warm rev (floor ${SETTLE_DAYS}d)..."
  FOUND=0
  for d in 1 2 3 5 7 10 "$SETTLE_DAYS"; do
    [ "$d" -gt "$SETTLE_DAYS" ] && continue
    rev=$(rev_as_of_days "$d") || rev=""
    if [ -z "$rev" ]; then echo "==> (could not resolve rev for -${d}d; skipping)" >&2; continue; fi
    phase "Trying nixpkgs @ -${d}d (${rev:0:12})..."
    if ! nix flake lock --override-input nixpkgs "github:nixos/nixpkgs/${rev}" >/dev/null 2>&1; then
      echo "==> (lock override failed for ${rev:0:12}; skipping)" >&2; continue
    fi
    if gate && [ -z "$(heavy_builds "$GATELOG")" ]; then
      CHOSEN_DAYS="$d"; FOUND=1
      phase "Cache-warm at -${d}d — download-only."
      break
    fi
  done
  if [ "$FOUND" -eq 0 ]; then
    [ "$AUTO" -eq 1 ] && notify_pending "no cache-warm rev within ${SETTLE_DAYS}d"
    echo "==> No download-only rev within ${SETTLE_DAYS}d. Cache still filling; retry later." >&2
    exit 3
  fi
else
  phase "HEAD is cache-warm — download-only."
fi

FETCH_LINE=$(grep -m1 'will be fetched' "$GATELOG" | sed -E 's/^[^(]*\(//; s/\).*//' || true)
NIXPKGS_REV=$(nix flake metadata "$WT" --json 2>/dev/null \
  | grep -oE '"nixpkgs"[^}]*"rev":"[0-9a-f]{40}"' | grep -oE '[0-9a-f]{40}' | head -1)

echo ""
phase "Update summary:"
echo "      target : nixpkgs ${NIXPKGS_REV:0:12} (settle -${CHOSEN_DAYS}d from HEAD)"
echo "      fetch  : ${FETCH_LINE:-cache}"
echo "      builds : local-only (expected/config-forced); no heavy uncached compiles"

if [ "$DRY" -eq 1 ]; then
  phase "--dry: no commit, no switch."
  exit 0
fi

if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git status --porcelain)" ]; then
  git add -A
  MSG="chore(flake): update nixpkgs to ${NIXPKGS_REV:0:12} (cache-warm, -${CHOSEN_DAYS}d)"
  phase "Committing: $MSG"
  git commit -q -m "$MSG"
else
  phase "No changes to commit (lock already current); nothing to do."
  exit 0
fi

NEW_COMMIT=$(git -C "$WT" rev-parse HEAD)

echo ""
phase "Building ($ACTION) — capped in heavy.slice so a runaway build can't OOM the session..."
set +e
if [ "$(id -u)" -eq 0 ]; then
  CAP=(systemd-run --scope --collect --quiet -p MemoryMax=22G -p MemorySwapMax=4G --)
elif command -v cage >/dev/null 2>&1; then
  CAP=(cage)
else
  CAP=()
fi
"${CAP[@]}" $SUDO nixos-rebuild "$ACTION" --flake "${WT}#${HOST}" 2>&1 \
  | tee /tmp/mandragora-update-rebuild.log \
  | grep --line-buffered -E "^(error:|building|activating|warning:|Failed|Done\.)"
RC=${PIPESTATUS[0]}
set -e

if [ "$RC" -ne 0 ] && ! grep -q "^Done\. The new configuration is " /tmp/mandragora-update-rebuild.log; then
  echo "==> FAILED before activation (rc=$RC). Log: /tmp/mandragora-update-rebuild.log" >&2
  [ "$AUTO" -eq 1 ] && notify_pending "rebuild failed rc=$RC"
  exit "$RC"
fi
phase "Switch ok (rc=$RC)."

if git -C "$WT" merge-base --is-ancestor "$MASTER_HEAD" "$NEW_COMMIT" 2>/dev/null \
   && git -C "$FLAKE" update-ref -m "mandragora-update: promote $NEW_COMMIT" \
        refs/heads/master "$NEW_COMMIT" "$MASTER_HEAD" 2>/dev/null; then
  phase "Promoted to master."
else
  phase "Master moved; rebasing onto it..."
  git -C "$WT" fetch "$FLAKE" master >/dev/null 2>&1
  git -C "$WT" rebase FETCH_HEAD || { echo "==> FAILED: rebase conflict in $WT." >&2; KEEP_WT=1; exit 1; }
  NEW_COMMIT=$(git -C "$WT" rev-parse HEAD)
  git -C "$FLAKE" update-ref refs/heads/master "$NEW_COMMIT"
fi

cd "$FLAKE"
ATTEMPTS=${MANDRAGORA_PUSH_ATTEMPTS:-3}
n=0
while true; do
  n=$((n + 1))
  if git fetch origin >/dev/null 2>&1 && \
     [ "$(git rev-list --count HEAD..origin/master 2>/dev/null || echo 0)" -gt 0 ]; then
    if ! git pull --rebase --autostash origin master; then
      if [ "$AUTO" -eq 1 ]; then
        echo "==> WARNING: origin diverged; leaving local master ahead (origin syncs on next interactive run)." >&2
        break
      fi
      echo "==> push rebase conflict." >&2; exit 1
    fi
  fi
  phase "Pushing (attempt $n/$ATTEMPTS)..."
  if git push; then break; fi
  if [ "$n" -ge "$ATTEMPTS" ]; then
    if [ "$AUTO" -eq 1 ]; then
      echo "==> WARNING: push failed under --auto; switch succeeded and local master is updated. Origin syncs on next interactive run." >&2
      break
    fi
    echo "==> FAILED: push rejected after $n attempts." >&2; exit 1
  fi
done

rm -f "$STATUSDIR/pending.txt" 2>/dev/null || true
phase "Done. nixpkgs now ${NIXPKGS_REV:0:12}."
