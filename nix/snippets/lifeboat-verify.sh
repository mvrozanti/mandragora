#!/usr/bin/env bash
set -euo pipefail

: "${RESTIC_REPOSITORY:?RESTIC_REPOSITORY must be set}"
: "${RESTIC_PASSWORD_FILE:?RESTIC_PASSWORD_FILE must be set}"
: "${AGE_KEY_FILE:?AGE_KEY_FILE must be set}"

NOTIFY="${MANDRAGORA_NOTIFY_BIN:-}"

problems=()

record() {
  echo "lifeboat: FAIL — $1" >&2
  problems+=("$1")
}

if [ ! -s "$AGE_KEY_FILE" ]; then
  record "age key missing or empty at $AGE_KEY_FILE"
elif pub=$(age-keygen -y "$AGE_KEY_FILE" 2>/dev/null) && [ -n "$pub" ]; then
  echo "lifeboat: age key valid (public: $pub)" >&2
else
  record "age key at $AGE_KEY_FILE is not a valid age identity"
fi

sftp_opts=(-o sftp.command="ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new opc@mandragora-vps -s sftp")

if ! restic "${sftp_opts[@]}" snapshots >/dev/null 2>&1; then
  record "restic repository unreachable or uninitialized"
elif restic "${sftp_opts[@]}" check --read-data-subset=2% >/dev/null 2>&1; then
  echo "lifeboat: restic check --read-data-subset=2% passed" >&2
else
  record "restic check --read-data-subset=2% failed (repository integrity)"
fi

if [ "${#problems[@]}" -gt 0 ]; then
  summary="lifeboat verification FAILED: ${problems[*]}"
  if [ -n "$NOTIFY" ]; then
    "$NOTIFY" "$summary" || true
  fi
  echo "$summary" >&2
  exit 1
fi

echo "lifeboat: all checks passed" >&2
