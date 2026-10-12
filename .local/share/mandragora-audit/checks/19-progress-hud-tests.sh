#!/usr/bin/env bash
set -uo pipefail
. "$AUDIT_HOME/lib/common.sh"

CHECK="${AUDIT_NAME:-progress-hud-tests}"
TESTS="$MANDRAGORA_REPO/agent-plugins/progress-hud/scripts/test_statusline.py"

if ! command -v python3 >/dev/null 2>&1; then
  audit_pass "$CHECK" "skipped (python3 not on PATH)"
  exit 0
fi

if out=$(python3 -S "$TESTS" 2>&1); then
  audit_pass "$CHECK" "$(printf '%s\n' "$out" | grep -m1 '^Ran ')"
  exit 0
fi

printf '%s\n' "$out" | tail -n 25 | sed 's/^/    /' >&2
audit_fail "$CHECK" "statusline unit tests failed; they pin the Bash-tool wrapper shape and the row layout"
exit 1
