#!/usr/bin/env bash
set -euo pipefail

: "${RESTIC_REPOSITORY:?RESTIC_REPOSITORY must be set}"
: "${RESTIC_PASSWORD_FILE:?RESTIC_PASSWORD_FILE must be set}"
: "${RESTIC_EXCLUDE_FILE:?RESTIC_EXCLUDE_FILE must be set}"
: "${BACKUP_PATHS:?BACKUP_PATHS must be set}"

NOTIFY="${MANDRAGORA_NOTIFY_BIN:-}"
LIMIT_UPLOAD="${RESTIC_LIMIT_UPLOAD_KIB:-0}"

notify() {
  [ -n "$NOTIFY" ] || return 0
  "$NOTIFY" "$1" || true
}

fail() {
  echo "backup: $1" >&2
  notify "restic backup FAILED: $1"
  exit 1
}

export RESTIC_PROGRESS_FPS=0

read -ra paths <<< "$BACKUP_PATHS"
present=()
for p in "${paths[@]}"; do
  if [ -e "$p" ]; then
    present+=("$p")
  else
    echo "backup: skipping absent path $p" >&2
  fi
done
[ "${#present[@]}" -gt 0 ] || fail "no backup paths present on disk"

sftp_opts=(-o sftp.command="ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new opc@mandragora-vps -s sftp")

if ! restic "${sftp_opts[@]}" snapshots >/dev/null 2>&1; then
  echo "backup: repository not initialized — running restic init" >&2
  restic "${sftp_opts[@]}" init || fail "restic init failed"
fi

backup_args=(
  "${sftp_opts[@]}"
  backup
  --exclude-file "$RESTIC_EXCLUDE_FILE"
  --exclude-caches
  --one-file-system
  --host mandragora-desktop
  --tag mandragora-desktop
)
if [ "$LIMIT_UPLOAD" -gt 0 ]; then
  backup_args+=(--limit-upload "$LIMIT_UPLOAD")
fi

echo "backup: snapshotting ${present[*]}" >&2
restic "${backup_args[@]}" "${present[@]}" || fail "restic backup failed"

echo "backup: applying retention policy" >&2
restic "${sftp_opts[@]}" forget \
  --host mandragora-desktop \
  --keep-daily 7 \
  --keep-weekly 4 \
  --keep-monthly 6 || fail "restic forget failed"

if [ "$(date +%u)" = "7" ]; then
  echo "backup: weekly prune" >&2
  restic "${sftp_opts[@]}" prune || fail "restic prune failed"
fi

echo "backup: done" >&2
