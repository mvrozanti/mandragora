# shellcheck shell=bash
DEPLOY_REMOTE="${DEPLOY_REMOTE:-${REMOTE:-opc@mandragora-vps}}"
DEPLOY_ROOT="${DEPLOY_ROOT:-/home/opc}"
DEPLOY_MODE="${DEPLOY_MODE:-deploy}"
DEPLOY_STAMPS=".deployed"
DEPLOY_SSH=(ssh -o BatchMode=yes -o ConnectTimeout=10)
DEPLOY_CHANGES=0

deploy_refuse() {
  printf 'REFUSED %s: %s\n' "${DEPLOY_STACK:-deploy}" "$*" >&2
  exit 3
}

deploy_writes() {
  [ "$DEPLOY_MODE" = deploy ] || [ "$DEPLOY_MODE" = adopt ]
}

deploy_begin() {
  DEPLOY_STACK="$1"
  local dir master slot
  dir="$(cd "$2" && pwd)"
  case "$DEPLOY_MODE" in deploy|check|adopt) ;; *) deploy_refuse "unknown DEPLOY_MODE '$DEPLOY_MODE'" ;; esac
  DEPLOY_REPO="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || deploy_refuse "$dir is not inside a git checkout"
  DEPLOY_COMMIT="$(git -C "$DEPLOY_REPO" rev-parse HEAD)"
  master="$(git -C "$DEPLOY_REPO" rev-parse refs/heads/master)"
  if deploy_writes && [ "${DEPLOY_FORCE:-0}" != 1 ]; then
    [ "$DEPLOY_COMMIT" = "$master" ] || deploy_refuse "deploys come from master only; this checkout is at ${DEPLOY_COMMIT:0:8}, master is at ${master:0:8}. Land the commit with mandragora-switch: it deploys what it lands."
    [ -z "$(git -C "$DEPLOY_REPO" status --porcelain -- "$dir")" ] || deploy_refuse "uncommitted changes under ${dir#"$DEPLOY_REPO"/}; only committed content is deployed"
  fi
  if deploy_writes && [ -z "${MANDRAGORA_SWITCH_LOCKED:-}" ]; then
    exec 8>"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/mandragora-switch.lock"
    flock -w 1800 8 || deploy_refuse "mandragora-switch held its lock for 30 minutes; gave up"
  fi
  slot="$("${DEPLOY_SSH[@]}" "$DEPLOY_REMOTE" "if [ -d $DEPLOY_ROOT/$DEPLOY_STACK ]; then echo present; sed -n 's/^commit=//p' $DEPLOY_ROOT/$DEPLOY_STAMPS/$DEPLOY_STACK 2>/dev/null || true; else echo absent; fi")" || deploy_refuse "cannot reach $DEPLOY_REMOTE"
  DEPLOY_SLOT="$(printf '%s\n' "$slot" | sed -n 1p)"
  DEPLOY_LIVE="$(printf '%s\n' "$slot" | sed -n 2p)"
  [ "$DEPLOY_MODE" = deploy ] || return 0
  if [ "${DEPLOY_FORCE:-0}" = 1 ]; then
    printf 'WARNING %s: --force: deploying %s over live %s\n' "$DEPLOY_STACK" "${DEPLOY_COMMIT:0:8}" "${DEPLOY_LIVE:-(unstamped)}" >&2
    return 0
  fi
  if [ -z "$DEPLOY_LIVE" ]; then
    [ "$DEPLOY_SLOT" = absent ] || deploy_refuse "live has no deploy stamp, so nothing proves what it holds. If it already matches master, enroll it: deploy-stacks.sh --adopt $DEPLOY_STACK. To overwrite it with master on purpose: --force"
    return 0
  fi
  git -C "$DEPLOY_REPO" cat-file -e "$DEPLOY_LIVE^{commit}" 2>/dev/null || deploy_refuse "live was deployed from ${DEPLOY_LIVE:0:8}, a commit master does not have (work that never landed)"
  git -C "$DEPLOY_REPO" merge-base --is-ancestor "$DEPLOY_LIVE" "$DEPLOY_COMMIT" || deploy_refuse "live (${DEPLOY_LIVE:0:8}) is newer than this checkout (${DEPLOY_COMMIT:0:8})"
}

deploy_rsync() {
  local args=("$@") last
  last="${args[-1]}"
  [ "${last:0:1}" = ":" ] && args[-1]="$DEPLOY_REMOTE:$DEPLOY_ROOT/$DEPLOY_STACK/${last:1}"
  if [ "$DEPLOY_MODE" = deploy ]; then
    rsync -a "${args[@]}"
    return
  fi
  local out
  out="$(rsync -nci -a "${args[@]}")" || return 1
  out="$(printf '%s\n' "$out" | grep -E '^(<|\*deleting|c[^d])' || true)"
  [ -n "$out" ] || return 0
  printf '%s\n' "$out" | sed "s/^/  $DEPLOY_STACK: /"
  DEPLOY_CHANGES=$((DEPLOY_CHANGES + $(printf '%s\n' "$out" | wc -l)))
}

deploy_remote() {
  [ "$DEPLOY_MODE" = deploy ] || return 0
  "${DEPLOY_SSH[@]}" "$DEPLOY_REMOTE" "cd $DEPLOY_ROOT/$DEPLOY_STACK && $*"
}

deploy_mkdir() {
  [ "$DEPLOY_MODE" = deploy ] || return 0
  local d paths=()
  for d in "" "$@"; do paths+=("$DEPLOY_ROOT/$DEPLOY_STACK/$d"); done
  "${DEPLOY_SSH[@]}" "$DEPLOY_REMOTE" "mkdir -p ${paths[*]}"
}

deploy_up() {
  [ "${NO_UP:-0}" = 1 ] && { printf '→ %s: files synced, not restarted (--no-up)\n' "$DEPLOY_STACK"; return 0; }
  deploy_remote "docker compose up -d $*"
}

deploy_stamp() {
  local body
  body="$(printf 'commit=%s\nat=%s\nfrom=%s\nhow=%s\n' "$DEPLOY_COMMIT" "$(date -u +%FT%TZ)" "$(hostname)" "$DEPLOY_MODE")"
  printf '%s\n' "$body" | "${DEPLOY_SSH[@]}" "$DEPLOY_REMOTE" "mkdir -p $DEPLOY_ROOT/$DEPLOY_STAMPS && cat > $DEPLOY_ROOT/$DEPLOY_STAMPS/$DEPLOY_STACK"
}

deploy_end() {
  case "$DEPLOY_MODE" in
    deploy)
      deploy_stamp
      printf '→ %s: live is now %s\n' "$DEPLOY_STACK" "${DEPLOY_COMMIT:0:8}"
      ;;
    check)
      if [ "$DEPLOY_CHANGES" -eq 0 ]; then
        printf '→ %s: live matches %s\n' "$DEPLOY_STACK" "${DEPLOY_COMMIT:0:8}"
      else
        printf '→ %s: %s difference(s) from live (listed above)\n' "$DEPLOY_STACK" "$DEPLOY_CHANGES"
        exit 10
      fi
      ;;
    adopt)
      [ "$DEPLOY_CHANGES" -eq 0 ] || deploy_refuse "live differs from master in $DEPLOY_CHANGES place(s) (listed above). Decide which side is right before enrolling: land live's changes in the repo, or deploy master with --force"
      deploy_stamp
      printf '→ %s: enrolled at %s (live already matched master)\n' "$DEPLOY_STACK" "${DEPLOY_COMMIT:0:8}"
      ;;
  esac
}
