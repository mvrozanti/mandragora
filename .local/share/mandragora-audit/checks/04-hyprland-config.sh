set -uo pipefail
. "$AUDIT_HOME/lib/common.sh"

CHECK="${AUDIT_NAME:-hyprland-config}"

mapfile -t HYPR_HITS < <(audit_changed_files | grep -E '^\.config/hypr/.*\.conf$' || true)

if [ "${#HYPR_HITS[@]}" -eq 0 ]; then
  audit_pass "$CHECK" "no hyprland config in scope"
  exit 0
fi

if ! command -v hyprctl >/dev/null 2>&1; then
  audit_pass "$CHECK" "hyprctl unavailable (non-desktop host); skipped"
  exit 0
fi

if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
  candidate=$(ls -1t "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr" 2>/dev/null | head -n1 || true)
  if [ -n "$candidate" ]; then
    export HYPRLAND_INSTANCE_SIGNATURE="$candidate"
  else
    audit_pass "$CHECK" "no running Hyprland instance; skipped"
    exit 0
  fi
fi

ERRS=$(hyprctl configerrors 2>/dev/null | sed '/^no errors$/d' | sed '/^$/d' || true)
if [ -z "$ERRS" ]; then
  audit_pass "$CHECK" "hyprctl configerrors empty"
  exit 0
fi

audit_fail "$CHECK" "hyprctl configerrors non-empty:"
printf '%s\n' "$ERRS" | sed 's/^/    /' >&2
echo "    Rule 11: Hyprland silently drops unknown fields. Fix the offending line(s) above." >&2
exit 1
