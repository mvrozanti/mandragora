# shellcheck shell=bash
set -uo pipefail
. "$AUDIT_HOME/lib/common.sh"

CHECK="${AUDIT_NAME:-phone-quality}"

if [ -z "${AUDIT_STAGED_FILES:-}" ]; then
  audit_pass "$CHECK" "runs on commits that touch the phone app or the bridges, and in phone-push"
  exit 0
fi

in_scope() {
  case "$1" in
    nix/hosts/mandragora-phone/app/*/build/*) return 1 ;;
    nix/hosts/mandragora-phone/app/*|nix/hosts/mandragora-phone/bridge/*|nix/hosts/mandragora-phone/quality/*) return 0 ;;
    .local/share/claude-bridge/*|.local/bin/phone-gate.sh|pyrightconfig.json) return 0 ;;
    *) return 1 ;;
  esac
}

touched=0
while IFS= read -r f; do
  [ -n "$f" ] && in_scope "$f" && touched=1
done < <(audit_changed_files)

[ "$touched" -eq 0 ] && { audit_pass "$CHECK" "no phone app or bridge files staged"; exit 0; }

ROOT=$(git rev-parse --show-toplevel)
GATE="$ROOT/.local/bin/phone-gate.sh"
[ -x "$GATE" ] || { audit_pass "$CHECK" "no phone-gate in this tree; skipped"; exit 0; }

LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT
if MANDRAGORA_REPO="$ROOT" "$GATE" fast > "$LOG" 2>&1; then
  audit_pass "$CHECK" "detekt, unit tests and coverage, ruff, basedpyright, bridge tests"
  exit 0
fi
audit_fail "$CHECK" "the phone quality gate failed"
grep -vE "is dirty|isLinux is deprecated" "$LOG" | tail -40 | sed 's/^/    /' >&2
echo "    run: MANDRAGORA_REPO=$ROOT $GATE fast" >&2
exit 1
