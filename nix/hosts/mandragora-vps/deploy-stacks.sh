#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$HERE/compose"
GUARD="$HERE/deploy-guard.sh"
MARKER=".no-deploy"
REL_COMPOSE="nix/hosts/mandragora-vps/compose"

MODE=deploy
NO_UP=0
ALL=0
SYNC=0
STACKS=()

usage() {
  cat >&2 <<EOF
Usage: deploy-stacks.sh [--check | --adopt | --sync] [--force] [--no-up] <stack>... | --all

The only writer of served content on mandragora-vps. Every deploy:
  * comes from master: refused from a worktree, a stale checkout, or a dirty stack dir;
  * moves forward: refused if live was deployed from a commit this checkout lacks;
  * stamps live with the commit it came from: /home/opc/<stack>/.deployed;
  * holds the mandragora-switch lock, so it never races a switch.

A stack with its own deploy.sh (that sources deploy-guard.sh) is deployed by
that script; any other stack is rsynced whole (.env- and .gitignore-safe) and
brought up with 'docker compose up -d'. Stacks marked $MARKER or RETIRED.md are
never deployed by this driver.

Modes:
  (default)  deploy the named stacks
  --check    list what a deploy would change on live; changes nothing
  --adopt    enroll stacks whose live content already equals master: stamp them,
             transfer nothing; refused if anything differs
  --sync     deploy every enrolled stack master has changed since its stamp, plus
             new stacks that have no slot on the VPS yet. mandragora-switch runs this
             after every landed commit; nobody needs to deploy by hand.
Options:
  --force    override the master, clean-tree and forward-only gates (says what it overwrites)
  --no-up    sync files, skip 'docker compose up -d'
  --all      every stack (with --check or --adopt)
EOF
}

die() { printf 'ERR: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --check|--dry-run|--diff) MODE=check; shift ;;
    --adopt) MODE=adopt; shift ;;
    --sync) SYNC=1; shift ;;
    --force) export DEPLOY_FORCE=1; shift ;;
    --no-up) NO_UP=1; shift ;;
    --all) ALL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; while [ $# -gt 0 ]; do STACKS+=("$1"); shift; done ;;
    -*) usage; die "unknown option: $1" ;;
    *) STACKS+=("$1"); shift ;;
  esac
done

[ -d "$COMPOSE_DIR" ] || die "compose dir not found: $COMPOSE_DIR"
[ -f "$GUARD" ] || die "deploy guard not found: $GUARD"
export DEPLOY_MODE="$MODE"

deployable() {
  local dir="$COMPOSE_DIR/$1"
  [ -d "$dir" ] && [ ! -f "$dir/$MARKER" ] && [ ! -f "$dir/RETIRED.md" ] \
    && { [ -f "$dir/docker-compose.yml" ] || [ -f "$dir/deploy.sh" ]; }
}

guarded_script() {
  [ -f "$COMPOSE_DIR/$1/deploy.sh" ] && grep -q 'deploy-guard.sh' "$COMPOSE_DIR/$1/deploy.sh"
}

collect_all() {
  local d name
  for d in "$COMPOSE_DIR"/*/; do
    name="$(basename "$d")"
    deployable "$name" && STACKS+=("$name")
  done
  return 0
}

collect_sync() {
  [ "$MODE" = deploy ] || die "--sync deploys; it does not combine with --check or --adopt"
  local repo slots d name stamp
  repo="$(git -C "$HERE" rev-parse --show-toplevel)"
  slots="$(ssh -o BatchMode=yes -o ConnectTimeout=10 "${DEPLOY_REMOTE:-${REMOTE:-opc@mandragora-vps}}" \
    'for d in /home/opc/*/; do n=$(basename "$d"); printf "%s %s\n" "$n" "$(sed -n "s/^commit=//p" "$d.deployed" 2>/dev/null)"; done')" \
    || die "cannot reach the VPS to read deploy stamps"
  for d in "$COMPOSE_DIR"/*/; do
    name="$(basename "$d")"
    deployable "$name" || continue
    if ! printf '%s\n' "$slots" | grep -q "^$name "; then
      STACKS+=("$name")
      continue
    fi
    stamp="$(printf '%s\n' "$slots" | sed -n "s/^$name //p")"
    [ -n "$stamp" ] || continue
    if git -C "$repo" cat-file -e "$stamp^{commit}" 2>/dev/null \
      && git -C "$repo" merge-base --is-ancestor "$stamp" HEAD \
      && git -C "$repo" diff --quiet "$stamp" HEAD -- "$REL_COMPOSE/$name"; then
      continue
    fi
    STACKS+=("$name")
  done
  return 0
}

if [ "$SYNC" -eq 1 ]; then
  [ "${#STACKS[@]}" -eq 0 ] && [ "$ALL" -eq 0 ] || die "--sync takes no stack names"
  collect_sync
  [ "${#STACKS[@]}" -gt 0 ] || { printf '→ served content: every enrolled stack matches master\n'; exit 0; }
elif [ "$ALL" -eq 1 ]; then
  [ "${#STACKS[@]}" -eq 0 ] || die "--all takes no stack names"
  [ "$MODE" != deploy ] || die "--all deploys nothing on its own; use --sync (what changed) or name the stacks"
  collect_all
fi

[ "${#STACKS[@]}" -gt 0 ] || { usage; die "no stacks given"; }

deploy_generic() {
  local name="$1" dir="$COMPOSE_DIR/$1"
  local filters=(
    --filter='P .env'
    --filter='P *.env'
    --exclude='.env'
    --exclude='*.env'
    --exclude="$MARKER"
    --exclude='.gitignore'
    --exclude='README.md'
    --exclude='RETIRED.md'
    --exclude='__pycache__/'
    --exclude='*.pyc'
  )
  [ -f "$dir/.gitignore" ] && filters+=(--exclude-from="$dir/.gitignore")
  # shellcheck source=/dev/null
  . "$GUARD"
  deploy_begin "$name" "$dir"
  deploy_mkdir
  deploy_rsync --delete "${filters[@]}" "$dir/" ":"
  deploy_up
  deploy_end
}

run_one() {
  local name="$1"
  if ! deployable "$name"; then
    printf 'skip %s: no deployable stack (missing, %s, RETIRED.md, or no docker-compose.yml)\n' "$name" "$MARKER" >&2
    return 1
  fi
  if [ -f "$COMPOSE_DIR/$name/deploy.sh" ]; then
    guarded_script "$name" || { printf 'skip %s: its deploy.sh does not use deploy-guard.sh\n' "$name" >&2; return 1; }
    NO_UP="$NO_UP" bash "$COMPOSE_DIR/$name/deploy.sh"
  else
    ( deploy_generic "$name" )
  fi
}

RC=0
for name in "${STACKS[@]}"; do
  set +e
  run_one "$name"
  rc=$?
  set -e
  if [ "$rc" -eq 10 ]; then
    RC=10
  elif [ "$rc" -ne 0 ]; then
    RC=1
  fi
done

exit "$RC"
