#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$HERE/compose"
REMOTE="${REMOTE:-opc@mandragora-vps}"
REMOTE_ROOT="${REMOTE_ROOT:-/home/opc}"
MARKER=".no-deploy"

DRY_RUN=0
DIFF=0
NO_UP=0
ALL=0
STACKS=()

usage() {
  cat >&2 <<EOF
Usage: deploy-stacks.sh [--dry-run] [--diff] [--no-up] <stack>... | --all

Unified deploy driver for the mandragora-vps compose stacks.

Per stack it rsyncs compose/<stack>/ to $REMOTE:$REMOTE_ROOT/<stack>/ with
--delete, then runs 'docker compose up -d' in that remote slot.

Safety:
  * Remote .env / *.env files are never sent and never deleted.
  * Each stack's own .gitignore is honoured (--exclude-from), so remote-only
    runtime state (data/, *_data/, generated reports, backups) is protected
    from --delete.
  * A stack directory carrying a '$MARKER' marker file is refused; --all skips
    it. Mark any stack whose remote state is live-only or has drifted from the
    repo so a blanket sync cannot clobber it.

Options:
  --dry-run   Show the rsync itemized plan; do not transfer, do not up.
  --diff      Alias for a compact rsync -ni change list per stack; implies no up.
  --no-up     Transfer files but skip 'docker compose up -d'.
  --all       Every compose/*/ dir with a docker-compose.yml (minus $MARKER'd).
  -h, --help  This help.

Environment:
  REMOTE        ssh target        default opc@mandragora-vps
  REMOTE_ROOT   remote slot root  default /home/opc
EOF
}

log() { printf '→ %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die() { printf 'ERR: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --diff) DIFF=1; NO_UP=1; shift ;;
    --no-up) NO_UP=1; shift ;;
    --all) ALL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; while [ $# -gt 0 ]; do STACKS+=("$1"); shift; done ;;
    -*) usage; die "unknown option: $1" ;;
    *) STACKS+=("$1"); shift ;;
  esac
done

[ -d "$COMPOSE_DIR" ] || die "compose dir not found: $COMPOSE_DIR"

collect_all() {
  local d name
  for d in "$COMPOSE_DIR"/*/; do
    name="$(basename "$d")"
    [ -f "$d/docker-compose.yml" ] || continue
    STACKS+=("$name")
  done
}

if [ "$ALL" -eq 1 ]; then
  [ "${#STACKS[@]}" -eq 0 ] || die "--all takes no explicit stack names"
  collect_all
fi

[ "${#STACKS[@]}" -gt 0 ] || { usage; die "no stacks given (pass names or --all)"; }

rsync_filters() {
  local dir="$1"
  RSYNC_FILTERS=(
    --filter='P .env'
    --filter='P *.env'
    --exclude='.env'
    --exclude='*.env'
    --exclude="$MARKER"
    --exclude='.gitignore'
    --exclude='README.md'
    --exclude='deploy.sh'
    --exclude='RETIRED.md'
    --exclude='__pycache__/'
    --exclude='*.pyc'
  )
  [ -f "$dir/.gitignore" ] && RSYNC_FILTERS+=(--exclude-from="$dir/.gitignore")
}

deploy_one() {
  local name="$1"
  local dir="$COMPOSE_DIR/$name"
  local dest="$REMOTE:$REMOTE_ROOT/$name/"

  if [ ! -d "$dir" ]; then
    warn "skip '$name': no such stack dir under compose/"
    return 1
  fi
  if [ ! -f "$dir/docker-compose.yml" ]; then
    warn "skip '$name': no docker-compose.yml (use its own deploy procedure)"
    return 1
  fi
  if [ -f "$dir/$MARKER" ]; then
    warn "skip '$name': $MARKER marker present (live-only/divergent; deploy manually)"
    return 1
  fi

  rsync_filters "$dir"

  if [ "$DIFF" -eq 1 ]; then
    log "diff $name  ($dir/ vs $dest)"
    rsync -ni -a --delete "${RSYNC_FILTERS[@]}" "$dir/" "$dest" \
      | grep -vE '^[[:space:]]*[0-9]' || true
    return 0
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log "dry-run rsync $name  ($dir/ → $dest)"
    rsync -ni -a --delete "${RSYNC_FILTERS[@]}" "$dir/" "$dest"
    log "dry-run: would 'docker compose up -d' in $REMOTE_ROOT/$name"
    return 0
  fi

  log "rsync $name → $dest"
  ssh "$REMOTE" "mkdir -p $REMOTE_ROOT/$name"
  rsync -a --delete "${RSYNC_FILTERS[@]}" "$dir/" "$dest"

  if [ "$NO_UP" -eq 1 ]; then
    log "$name: files synced (--no-up, stack not restarted)"
    return 0
  fi

  log "docker compose up -d in $REMOTE_ROOT/$name"
  ssh "$REMOTE" "cd $REMOTE_ROOT/$name && docker compose up -d"
  log "$name: up"
}

RC=0
for name in "${STACKS[@]}"; do
  deploy_one "$name" || RC=1
done

exit "$RC"
