#!/usr/bin/env bash
set -uo pipefail
. "$AUDIT_HOME/lib/common.sh"

CHECK="${AUDIT_NAME:-statusline-refresh}"

if ! command -v python3 >/dev/null 2>&1; then
  audit_pass "$CHECK" "skipped (python3 not on PATH)"
  exit 0
fi

mapfile -t files < <(git ls-files -- '*.json' | xargs -r grep -l '"statusLine"' 2>/dev/null)
if [ "${#files[@]}" -eq 0 ]; then
  audit_pass "$CHECK" "no tracked settings file declares a statusLine"
  exit 0
fi

if out=$(python3 -S "$AUDIT_HOME/lib/statusline-refresh.py" "${files[@]}" 2>&1); then
  audit_pass "$CHECK" "$out"
  exit 0
fi

printf '%s\n' "$out" | sed 's/^/    /' >&2
audit_fail "$CHECK" "a claude-progressbar statusLine without refreshInterval freezes every bar (vault: features/Progress bars for running commands in the Claude Code statusline)"
exit 1
