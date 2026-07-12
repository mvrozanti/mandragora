#!/usr/bin/env bash
set -euo pipefail

: "${RESTIC_PASSWORD_FILE:?RESTIC_PASSWORD_FILE must be set}"

if [ -s "$RESTIC_PASSWORD_FILE" ]; then
  exit 0
fi

dir=$(dirname "$RESTIC_PASSWORD_FILE")
mkdir -p "$dir"
umask 077
openssl rand -base64 32 > "$RESTIC_PASSWORD_FILE"
echo "backup: generated new restic password file" >&2
