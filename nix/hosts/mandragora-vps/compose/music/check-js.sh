#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
for f in "$HERE"/static/js/*.js; do
  cp "$f" "$TMP/$(basename "${f%.js}").mjs"
  if node --check "$TMP/$(basename "${f%.js}").mjs"; then
    echo "ok   $(basename "$f")"
  else
    echo "FAIL $(basename "$f")"
    fail=1
  fi
done
exit "$fail"
