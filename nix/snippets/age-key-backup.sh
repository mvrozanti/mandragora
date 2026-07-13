#!/usr/bin/env bash
set -euo pipefail

: "${AGE_KEY_FILE:?AGE_KEY_FILE must be set}"
: "${BACKUP_USER:?BACKUP_USER must be set}"
: "${REMOTE_USER:?REMOTE_USER must be set}"
: "${VPS_HOST:?VPS_HOST must be set}"
: "${REMOTE_DIR:?REMOTE_DIR must be set}"

NOTIFY="${MANDRAGORA_NOTIFY_BIN:-}"

notify() {
  [ -n "$NOTIFY" ] || return 0
  "$NOTIFY" "$1" || true
}

fail() {
  echo "age-key-backup: $1" >&2
  notify "age-key-backup FAILED: $1"
  exit 1
}

if [ ! -s "$AGE_KEY_FILE" ]; then
  fail "age key missing or empty at $AGE_KEY_FILE"
fi

if ! age-keygen -y "$AGE_KEY_FILE" >/dev/null 2>&1; then
  fail "age key at $AGE_KEY_FILE is not a valid age identity"
fi

ssh_opts=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new)
remote="${REMOTE_USER}@${VPS_HOST}"

if ! runuser -u "$BACKUP_USER" -- ssh "${ssh_opts[@]}" "$remote" \
    "umask 077; mkdir -p ${REMOTE_DIR} && cat > ${REMOTE_DIR}/keys.txt" \
    < "$AGE_KEY_FILE"; then
  fail "streaming age key to $remote failed"
fi

local_hash=$(sha256sum < "$AGE_KEY_FILE" | cut -d' ' -f1)
[ -n "$local_hash" ] || fail "could not compute local age key hash"

remote_hash=$(runuser -u "$BACKUP_USER" -- ssh "${ssh_opts[@]}" "$remote" \
  "sha256sum ${REMOTE_DIR}/keys.txt" | cut -d' ' -f1) \
  || fail "could not compute remote age key hash"

if [ "$local_hash" != "$remote_hash" ]; then
  fail "hash mismatch after upload (local != remote)"
fi

echo "age-key-backup: mirrored and verified age key on $remote" >&2
