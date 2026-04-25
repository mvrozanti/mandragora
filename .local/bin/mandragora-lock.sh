#!/usr/bin/env bash
set -euo pipefail

LOCK_DIR="/dev/shm/mandragora-locks"
REPO="/etc/nixos/mandragora"
LEGACY_LOCK="/dev/shm/mandragora-agent-lock"
CLAIM_GUARD="$LOCK_DIR/.claim.lock"

mkdir -p "$LOCK_DIR"
chmod 0700 "$LOCK_DIR" 2>/dev/null || true

if [ -e "$LEGACY_LOCK" ]; then
  echo "mandragora-lock: removing obsolete legacy lock at $LEGACY_LOCK" >&2
  rm -f "$LEGACY_LOCK"
fi

is_pid_alive() {
  local pid="$1"
  [[ -z "$pid" ]] && return 2
  [[ "$pid" =~ ^[0-9]+$ ]] || return 2
  [[ "$pid" -le 1 ]] && return 2
  kill -0 "$pid" 2>/dev/null
}

now_iso() { date -u +%FT%TZ; }

duration_to_iso() {
  local d="$1"
  if date -u -d "+$d" +%FT%TZ >/dev/null 2>&1; then
    date -u -d "+$d" +%FT%TZ
  else
    date -u -d "$d" +%FT%TZ
  fi
}

iso_to_epoch() {
  date -u -d "$1" +%s 2>/dev/null || echo 0
}

gen_uuid() { cat /proc/sys/kernel/random/uuid; }

usage() {
  cat <<'EOF'
mandragora-lock — scope-based concurrent lock for /etc/nixos/mandragora/

Usage:
  mandragora-lock claim   [--session ID] [--paths "p1 p2"] [--scope "..."]
                          [--phase edit|commit] [--ttl 15min] [--agent ID]
                          [--wait SECONDS] [--owner-pid PID]
  mandragora-lock release <session-id>
  mandragora-lock extend  <session-id> [--ttl 15min]
  mandragora-lock list
  mandragora-lock check   [same options as claim]
  mandragora-lock prune   [--force]

Liveness:
  --owner-pid is the long-lived process holding the lock (e.g. mandragora-switch's
  shell). When set and that PID is dead AND the lock file is >30s old, the lock
  is automatically pruned during claim/check/prune. Without --owner-pid, locks
  are TTL-only (default for ephemeral tool-call agents).

Path semantics (--paths):
  Space-separated git pathspecs. Default: "*" (whole repo).
  Two 'edit' locks conflict iff their declared pathspecs match at least one
  shared tracked file in $REPO. The literal string "*" or "**" means whole-repo.
  A 'commit' lock conflicts with every other active lock — it's exclusive.

Prune:
  Default: removes stale-pid locks (verifiable) and expired locks (TTL-based).
  --force: removes ALL locks unconditionally. Break-glass only.

Output:
  claim/extend/release print the session-id on success.
  claim/check exit non-zero with conflict details on failure.
EOF
}

parse_lock() {
  local file="$1"
  LOCK_AGENT=""; LOCK_SESSION=""; LOCK_PHASE="edit"
  LOCK_EXPIRES_EPOCH=0; LOCK_SCOPE=""; LOCK_PID=""; LOCK_OWNER_PID=""
  LOCK_PATHS=()
  local in_paths=0
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$in_paths" -eq 1 ]; then
      if [[ "$line" =~ ^[[:space:]]+([^[:space:]].*)$ ]]; then
        LOCK_PATHS+=("${BASH_REMATCH[1]}")
        continue
      else
        in_paths=0
      fi
    fi
    case "$line" in
      "agent: "*)   LOCK_AGENT="${line#agent: }" ;;
      "session: "*) LOCK_SESSION="${line#session: }" ;;
      "phase: "*)   LOCK_PHASE="${line#phase: }" ;;
      "pid: "*)         LOCK_PID="${line#pid: }" ;;
      "owner_pid: "*)   LOCK_OWNER_PID="${line#owner_pid: }" ;;
      "expires: "*) LOCK_EXPIRES_EPOCH=$(iso_to_epoch "${line#expires: }") ;;
      "scope: "*)   LOCK_SCOPE="${line#scope: }" ;;
      "paths:")     in_paths=1 ;;
    esac
  done < "$file"
}

list_lock_files() {
  shopt -s nullglob
  for f in "$LOCK_DIR"/*; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in .*) continue ;; esac
    printf '%s\n' "$f"
  done
  shopt -u nullglob
}

is_lock_stale() {
  local file="$1"
  parse_lock "$file"
  [ -z "$LOCK_OWNER_PID" ] && return 1
  is_pid_alive "$LOCK_OWNER_PID"
  local rc=$?
  [ "$rc" -eq 1 ] || return 1
  local mtime now
  mtime=$(stat -c %Y "$file" 2>/dev/null || echo 0)
  now=$(date -u +%s)
  [ $((now - mtime)) -ge 30 ]
}

is_wildcard_path() {
  case "$1" in '*'|'**'|'**/*'|'.'|'') return 0 ;; *) return 1 ;; esac
}

paths_overlap() {
  local -n A_REF=$1
  local -n B_REF=$2
  local p
  for p in "${A_REF[@]}"; do is_wildcard_path "$p" && return 0; done
  for p in "${B_REF[@]}"; do is_wildcard_path "$p" && return 0; done
  local x y
  for x in "${A_REF[@]}"; do
    for y in "${B_REF[@]}"; do
      [ "$x" = "$y" ] && return 0
    done
  done
  local a_files b_files
  a_files=$(cd "$REPO" 2>/dev/null && git ls-files -- "${A_REF[@]}" 2>/dev/null | sort -u || true)
  b_files=$(cd "$REPO" 2>/dev/null && git ls-files -- "${B_REF[@]}" 2>/dev/null | sort -u || true)
  if [ -n "$a_files" ] && [ -n "$b_files" ]; then
    if comm -12 <(printf '%s\n' "$a_files") <(printf '%s\n' "$b_files") | grep -q .; then
      return 0
    fi
  fi
  for x in "${A_REF[@]}"; do
    for y in "${B_REF[@]}"; do
      case "$y" in "$x"/*) return 0 ;; esac
      case "$x" in "$y"/*) return 0 ;; esac
    done
  done
  return 1
}

check_conflicts() {
  local session="$1" phase="$2"; shift 2
  local -a paths=("$@")
  local conflicts=""
  local f
  while IFS= read -r f; do
    [ -e "$f" ] || continue
    if is_lock_stale "$f"; then
      parse_lock "$f"
      printf 'mandragora-lock: pruning stale lock %s (owner_pid=%s dead, agent=%s)\n' \
        "$LOCK_SESSION" "$LOCK_OWNER_PID" "$LOCK_AGENT" >&2
      rm -f "$f"
      continue
    fi
    parse_lock "$f"
    [ "$LOCK_SESSION" = "$session" ] && continue
    if [ "$phase" = "commit" ] || [ "$LOCK_PHASE" = "commit" ]; then
      conflicts+="  ${LOCK_SESSION} (phase=$LOCK_PHASE agent=$LOCK_AGENT scope='$LOCK_SCOPE')"$'\n'
      continue
    fi
    local -a other=("${LOCK_PATHS[@]}")
    if paths_overlap paths other; then
      conflicts+="  ${LOCK_SESSION} (paths overlap, agent=$LOCK_AGENT scope='$LOCK_SCOPE')"$'\n'
    fi
  done < <(list_lock_files)
  if [ -n "$conflicts" ]; then
    printf 'mandragora-lock: claim conflict\n%s' "$conflicts"
    return 1
  fi
  return 0
}

write_lock() {
  local session="$1" agent="$2" phase="$3" started="$4" expires="$5" scope="$6" owner_pid="$7"; shift 7
  local lockfile="$LOCK_DIR/$session"
  local tmp="$lockfile.tmp.$$"
  {
    printf 'agent: %s\n' "$agent"
    printf 'session: %s\n' "$session"
    printf 'pid: %s\n' "$$"
    [ -n "$owner_pid" ] && printf 'owner_pid: %s\n' "$owner_pid"
    printf 'phase: %s\n' "$phase"
    printf 'started: %s\n' "$started"
    printf 'expires: %s\n' "$expires"
    [ -n "$scope" ] && printf 'scope: %s\n' "$scope"
    printf 'paths:\n'
    local p
    for p in "$@"; do printf '  %s\n' "$p"; done
  } > "$tmp"
  mv -f "$tmp" "$lockfile"
}

cmd_claim_or_check() {
  local mode="$1"; shift
  local session="" phase="edit" ttl="15min" scope="" wait_secs=0 owner_pid=""
  local agent="${MANDRAGORA_AGENT:-${AGENT:-${USER:-unknown}}}"
  local -a paths=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --session)   session="$2"; shift 2 ;;
      --agent)     agent="$2"; shift 2 ;;
      --phase)     phase="$2"; shift 2 ;;
      --ttl)       ttl="$2"; shift 2 ;;
      --scope)     scope="$2"; shift 2 ;;
      --paths)     read -ra paths <<<"$2"; shift 2 ;;
      --wait)      wait_secs="$2"; shift 2 ;;
      --owner-pid) owner_pid="$2"; shift 2 ;;
      --)          shift; while [ $# -gt 0 ]; do paths+=("$1"); shift; done ;;
      -*)          echo "unknown flag: $1" >&2; exit 2 ;;
      *)           paths+=("$1"); shift ;;
    esac
  done
  [ "${#paths[@]}" -gt 0 ] || paths=("*")
  case "$phase" in edit|commit) ;; *) echo "phase must be edit|commit" >&2; exit 2 ;; esac
  [ -n "$session" ] || session=$(gen_uuid)

  exec 9>"$CLAIM_GUARD"
  flock -x 9

  local deadline=$(( $(date -u +%s) + wait_secs ))
  local conflict_msg=""
  while :; do
    if conflict_msg=$(check_conflicts "$session" "$phase" "${paths[@]}"); then
      break
    fi
    if [ "$(date -u +%s)" -ge "$deadline" ]; then
      printf '%s' "$conflict_msg" >&2
      flock -u 9
      exit 1
    fi
    flock -u 9
    sleep 2
    flock -x 9
  done

  if [ "$mode" = "check" ]; then
    flock -u 9
    echo "ok"
    return 0
  fi

  local started expires
  started=$(now_iso)
  expires=$(duration_to_iso "$ttl")
  write_lock "$session" "$agent" "$phase" "$started" "$expires" "$scope" "$owner_pid" "${paths[@]}"
  flock -u 9
  echo "$session"
}

cmd_release() {
  local session=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --session) session="$2"; shift 2 ;;
      *)         session="$1"; shift ;;
    esac
  done
  [ -n "$session" ] || { echo "release: session-id required" >&2; exit 2; }
  local f="$LOCK_DIR/$session"
  if [ -e "$f" ]; then
    rm -f "$f"
    echo "released $session"
  else
    echo "no such lock: $session" >&2
    exit 1
  fi
}

cmd_extend() {
  local session="" ttl="15min"
  while [ $# -gt 0 ]; do
    case "$1" in
      --session) session="$2"; shift 2 ;;
      --ttl)     ttl="$2"; shift 2 ;;
      *)         session="$1"; shift ;;
    esac
  done
  [ -n "$session" ] || { echo "extend: session-id required" >&2; exit 2; }
  local f="$LOCK_DIR/$session"
  [ -e "$f" ] || { echo "no such lock: $session" >&2; exit 1; }
  local new_expires
  new_expires=$(duration_to_iso "$ttl")
  if grep -q '^expires:' "$f"; then
    sed -i "s|^expires:.*|expires: $new_expires|" "$f"
  else
    printf 'expires: %s\n' "$new_expires" >> "$f"
  fi
  echo "$session expires $new_expires"
}

cmd_list() {
  local now
  now=$(date -u +%s)
  local found=0 f
  while IFS= read -r f; do
    [ -e "$f" ] || continue
    found=1
    local stat="active"
    if is_lock_stale "$f"; then
      stat="STALE-PID"
    else
      parse_lock "$f"
      [ "$LOCK_EXPIRES_EPOCH" -lt "$now" ] && stat="EXPIRED"
    fi
    parse_lock "$f"
    printf '=== %s [%s] ===\n' "$LOCK_SESSION" "$stat"
    printf '  agent:      %s\n' "$LOCK_AGENT"
    printf '  phase:      %s\n' "$LOCK_PHASE"
    [ -n "$LOCK_OWNER_PID" ] && printf '  owner_pid:  %s\n' "$LOCK_OWNER_PID"
    [ -n "$LOCK_SCOPE" ] && printf '  scope:      %s\n' "$LOCK_SCOPE"
    printf '  paths:\n'
    local p
    for p in "${LOCK_PATHS[@]}"; do printf '    %s\n' "$p"; done
    echo
  done < <(list_lock_files)
  if [ "$found" -eq 0 ]; then
    echo "(no active locks)"
  fi
}

cmd_prune() {
  local force=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --force|-f) force=1; shift ;;
      *) echo "prune: unknown arg: $1" >&2; exit 2 ;;
    esac
  done
  exec 9>"$CLAIM_GUARD"
  flock -x 9
  local now
  now=$(date -u +%s)
  local removed=0 f
  while IFS= read -r f; do
    [ -e "$f" ] || continue
    if [ "$force" -eq 1 ]; then
      parse_lock "$f"
      rm -f "$f"
      echo "pruned (force): $LOCK_SESSION (agent=$LOCK_AGENT)"
      removed=$((removed + 1))
      continue
    fi
    if is_lock_stale "$f"; then
      parse_lock "$f"
      rm -f "$f"
      echo "pruned stale-pid: $LOCK_SESSION (owner_pid=$LOCK_OWNER_PID dead, agent=$LOCK_AGENT)"
      removed=$((removed + 1))
      continue
    fi
    parse_lock "$f"
    if [ "$LOCK_EXPIRES_EPOCH" -lt "$now" ]; then
      rm -f "$f"
      echo "pruned expired: $LOCK_SESSION (agent=$LOCK_AGENT)"
      removed=$((removed + 1))
    fi
  done < <(list_lock_files)
  flock -u 9
  if [ "$removed" -eq 0 ]; then
    echo "(nothing to prune)"
  fi
}

main() {
  local cmd="${1:-help}"; shift || true
  case "$cmd" in
    claim)             cmd_claim_or_check claim "$@" ;;
    check)             cmd_claim_or_check check "$@" ;;
    release)           cmd_release "$@" ;;
    extend)            cmd_extend "$@" ;;
    list|ls|status)    cmd_list "$@" ;;
    prune)             cmd_prune "$@" ;;
    help|-h|--help|"") usage ;;
    *)                 echo "unknown command: $cmd" >&2; usage; exit 2 ;;
  esac
}

main "$@"
