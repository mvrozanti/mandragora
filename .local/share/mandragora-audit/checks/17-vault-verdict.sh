# shellcheck shell=bash
set -uo pipefail
. "$AUDIT_HOME/lib/common.sh"

CHECK="${AUDIT_NAME:-vault-verdict}"

if [ -z "${COMMIT_MSG_FILE:-}" ] || [ ! -f "$COMMIT_MSG_FILE" ]; then
  audit_pass "$CHECK" "skipped (commit-msg only)"
  exit 0
fi

if ! command -v mandragora-vault >/dev/null 2>&1; then
  audit_pass "$CHECK" "skipped (mandragora-vault not installed yet)"
  exit 0
fi

if mandragora-vault trailer-check "$COMMIT_MSG_FILE"; then
  audit_pass "$CHECK"
  exit 0
fi

audit_fail "$CHECK" "agent commit without a valid Vault: line"
exit 1
