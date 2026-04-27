#!/usr/bin/env bash
set -eo pipefail

LOCK_DIR="/dev/shm/gpu-lock"
CLAIM_LOCK="$LOCK_DIR/.claim.lock"
PRUNE_AGE_SECONDS=30

mkdir -p "$LOCK_DIR"

usage() {
  cat >&2 <<EOF
gpu-lock — whole-GPU mutex for Mandragora workloads.

Usage:
  gpu-lock claim --workload {llm|imagegen|trading|other} \\
                 --scope "<short description>" \\
                 [--eta <duration>] [--owner-pid <pid>]
  gpu-lock release <session>
  gpu-lock list
  gpu-lock prune

Premise: GPU is whole-or-nothing. One workload at a time.
Lock dir: $LOCK_DIR (RAM-backed, auto-clears on reboot).
EOF
  exit 1
}

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
now_epoch() { date +%s; }

iso_to_epoch() {
  date -d "$1" +%s 2>/dev/null || echo 0
}

duration_to_seconds() {
  local s="$1"
  case "$s" in
    *h) echo $((${s%h} * 3600));;
    *m|*min) echo $((${s%m*} * 60));;
    *s|*sec) echo $((${s%s*}));;
    *) echo "$s";;
  esac
}

pid_alive() {
  local pid="$1"
  [ -n "$pid" ] && [ "$pid" != "0" ] && kill -0 "$pid" 2>/dev/null
}

read_field() {
  local file="$1" field="$2"
  awk -v f="$field" 'BEGIN{FS=": "} $1==f {sub(/^[^:]+: /,""); print; exit}' "$file"
}

prune_dead() {
  local now file pid mtime age
  now=$(now_epoch)
  shopt -s nullglob
  for file in "$LOCK_DIR"/*.lock; do
    [ -f "$file" ] || continue
    [ "$(basename "$file")" = ".claim.lock" ] && continue
    pid=$(read_field "$file" owner_pid)
    if [ -n "$pid" ] && [ "$pid" != "0" ] && ! pid_alive "$pid"; then
      mtime=$(stat -c %Y "$file" 2>/dev/null || echo 0)
      age=$(( now - mtime ))
      if [ "$age" -ge "$PRUNE_AGE_SECONDS" ]; then
        echo "==> pruning stale lock $(basename "$file") (pid $pid dead, age ${age}s)" >&2
        rm -f "$file"
      fi
    fi
  done
  shopt -u nullglob
}

list_locks() {
  shopt -s nullglob
  local files=("$LOCK_DIR"/*.lock)
  shopt -u nullglob
  local actual=()
  for f in "${files[@]}"; do
    [ "$(basename "$f")" = ".claim.lock" ] && continue
    actual+=("$f")
  done
  if [ ${#actual[@]} -eq 0 ]; then
    echo "(no active GPU locks)"
    return 0
  fi
  for f in "${actual[@]}"; do
    echo "--- $(basename "$f")"
    cat "$f"
    echo
  done
}

cmd_claim() {
  local workload="" scope="" eta_arg="" owner_pid="" agent
  while [ $# -gt 0 ]; do
    case "$1" in
      --workload) workload="$2"; shift 2;;
      --scope) scope="$2"; shift 2;;
      --eta) eta_arg="$2"; shift 2;;
      --owner-pid) owner_pid="$2"; shift 2;;
      *) echo "unknown arg: $1" >&2; usage;;
    esac
  done
  [ -n "$workload" ] || { echo "--workload required" >&2; usage; }
  [ -n "$scope" ] || { echo "--scope required" >&2; usage; }
  case "$workload" in
    llm|imagegen|trading|other) ;;
    *) echo "invalid --workload (use: llm|imagegen|trading|other)" >&2; exit 1;;
  esac

  agent="${USER}@$(hostname -s)"
  [ -n "${SUDO_USER:-}" ] && agent="sudo:${SUDO_USER}@$(hostname -s)"

  exec 8>"$CLAIM_LOCK"
  flock 8

  prune_dead

  shopt -s nullglob
  for existing in "$LOCK_DIR"/*.lock; do
    [ "$(basename "$existing")" = ".claim.lock" ] && continue
    [ -f "$existing" ] || continue
    local existing_pid existing_workload existing_scope existing_agent
    existing_pid=$(read_field "$existing" owner_pid)
    existing_workload=$(read_field "$existing" workload)
    existing_scope=$(read_field "$existing" scope)
    existing_agent=$(read_field "$existing" agent)
    if [ -n "$existing_pid" ] && [ "$existing_pid" != "0" ] && ! pid_alive "$existing_pid"; then
      echo "==> pruning stale lock (pid $existing_pid dead) before claim" >&2
      rm -f "$existing"
      continue
    fi
    cat >&2 <<EOF
==> CLAIM REJECTED — GPU is held.

  $(basename "$existing")
$(sed 's/^/    /' "$existing")

The holder is live (pid $existing_pid). Wait or coordinate with them.
If you are sure they are stuck, ask the user before forcing release.
EOF
    exit 2
  done
  shopt -u nullglob

  local session started eta=""
  session=$(printf '%(%Y%m%dT%H%M%SZ)T-%s\n' -1 "$(od -An -N4 -tx4 /dev/urandom | tr -d ' ')")
  started=$(now_iso)
  if [ -n "$eta_arg" ]; then
    local secs
    secs=$(duration_to_seconds "$eta_arg")
    if [ "$secs" -gt 0 ]; then
      eta=$(date -u -d "@$(( $(now_epoch) + secs ))" +%Y-%m-%dT%H:%M:%SZ)
    fi
  fi

  local file="$LOCK_DIR/$session.lock"
  {
    echo "session: $session"
    echo "workload: $workload"
    echo "scope: $scope"
    echo "agent: $agent"
    echo "started: $started"
    [ -n "$eta" ] && echo "eta: $eta"
    [ -n "$owner_pid" ] && echo "owner_pid: $owner_pid"
  } > "$file"

  echo "$session"
}

cmd_release() {
  local session="$1"
  [ -n "$session" ] || { echo "session required" >&2; usage; }
  local file="$LOCK_DIR/$session.lock"
  if [ ! -f "$file" ]; then
    echo "==> no lock named $session" >&2
    exit 1
  fi
  rm -f "$file"
  echo "==> released $session"
}

cmd=${1:-}
[ -n "$cmd" ] || usage
shift || true

case "$cmd" in
  claim)   cmd_claim "$@";;
  release) cmd_release "$@";;
  list)    list_locks;;
  prune)   prune_dead; list_locks;;
  -h|--help|help) usage;;
  *) echo "unknown subcommand: $cmd" >&2; usage;;
esac
