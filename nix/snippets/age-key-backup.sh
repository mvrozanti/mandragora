#!/usr/bin/env bash
set -euo pipefail

: "${AGE_KEY_FILE:?AGE_KEY_FILE must be set}"
: "${BACKUP_USER:?BACKUP_USER must be set}"
: "${REMOTE_USER:?REMOTE_USER must be set}"
: "${VPS_HOST:?VPS_HOST must be set}"
: "${REMOTE_DIR:?REMOTE_DIR must be set}"
: "${LIFEBOAT_RECIPIENT:?LIFEBOAT_RECIPIENT must be set}"

NOTIFY="${MANDRAGORA_NOTIFY_BIN:-}"
CIPHER=""

notify() {
  [ -n "$NOTIFY" ] || return 0
  "$NOTIFY" "$1" || true
}

cleanup() {
  [ -n "$CIPHER" ] && [ -f "$CIPHER" ] && rm -f "$CIPHER"
  return 0
}
trap cleanup EXIT

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

CIPHER=$(mktemp)
chmod 600 "$CIPHER"

if ! age --encrypt --recipient "$LIFEBOAT_RECIPIENT" -o "$CIPHER" "$AGE_KEY_FILE"; then
  fail "could not encrypt age key to lifeboat recipient $LIFEBOAT_RECIPIENT"
fi

if ! head -c 21 "$CIPHER" | grep -q 'age-encryption.org'; then
  fail "encrypted artifact is not an age file; refusing to upload"
fi

if grep -q 'AGE-SECRET-KEY-' "$CIPHER"; then
  fail "encrypted artifact still contains raw key material; refusing to upload"
fi

ssh_opts=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new)
remote="${REMOTE_USER}@${VPS_HOST}"

if ! runuser -u "$BACKUP_USER" -- ssh "${ssh_opts[@]}" "$remote" \
    "umask 077; mkdir -p ${REMOTE_DIR} && cat > ${REMOTE_DIR}/keys.txt.age" \
    < "$CIPHER"; then
  fail "streaming encrypted age key to $remote failed"
fi

local_hash=$(sha256sum < "$CIPHER" | cut -d' ' -f1)
[ -n "$local_hash" ] || fail "could not compute local ciphertext hash"

remote_hash=$(runuser -u "$BACKUP_USER" -- ssh "${ssh_opts[@]}" "$remote" \
  "sha256sum ${REMOTE_DIR}/keys.txt.age" | cut -d' ' -f1) \
  || fail "could not compute remote ciphertext hash"

if [ "$local_hash" != "$remote_hash" ]; then
  fail "hash mismatch after upload (local != remote)"
fi

runuser -u "$BACKUP_USER" -- ssh "${ssh_opts[@]}" "$remote" \
  "rm -f ${REMOTE_DIR}/keys.txt" \
  || echo "age-key-backup: warning: could not remove legacy plaintext keys.txt" >&2

echo "age-key-backup: mirrored and verified lifeboat-encrypted age key on $remote" >&2
