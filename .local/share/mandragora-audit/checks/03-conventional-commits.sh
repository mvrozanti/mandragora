set -uo pipefail
. "$AUDIT_HOME/lib/common.sh"

CHECK="${AUDIT_NAME:-conventional-commits}"

# Two modes:
#   commit-msg hook:  COMMIT_MSG_FILE points at the candidate message; we lint it.
#   standalone:       lint HEAD's subject (post-hoc audit; useful for back-fills).

if [ -n "${COMMIT_MSG_FILE:-}" ] && [ -f "$COMMIT_MSG_FILE" ]; then
  subject=$(grep -vE '^\s*#' "$COMMIT_MSG_FILE" | sed '/^[[:space:]]*$/d' | head -n1)
  source="$COMMIT_MSG_FILE"
else
  subject=$(git log -1 --format=%s 2>/dev/null || true)
  source="HEAD"
fi

# Skip merge commits + revert auto-subjects.
case "$subject" in
  'Merge '*|'Revert "'*) audit_pass "$CHECK" "skipped (merge/revert)"; exit 0 ;;
  '') audit_fail "$CHECK" "$source has empty subject"; exit 1 ;;
esac

# <type>[(scope)][!]: <description>
# type ∈ feat|fix|docs|refactor|chore|build|ci|test|perf|style|revert
# description: starts lowercase, no trailing period.
re='^(feat|fix|docs|refactor|chore|build|ci|test|perf|style|revert)(\([a-z0-9_./-]+\))?!?:\ [a-z].*[^.]$'

if [[ "$subject" =~ $re ]]; then
  audit_pass "$CHECK" "$subject"
  exit 0
fi

audit_fail "$CHECK" "$source: $subject"
echo "    Format: <type>[(scope)][!]: <imperative lowercase description>" >&2
echo "    Types:  feat|fix|docs|refactor|chore|build|ci|test|perf|style|revert" >&2
exit 1
