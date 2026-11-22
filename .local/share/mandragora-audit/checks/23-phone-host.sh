# shellcheck shell=bash
set -uo pipefail
. "$AUDIT_HOME/lib/common.sh"

CHECK="${AUDIT_NAME:-phone-host}"
BRIDGE="${MANDRAGORA_PHONE_BRIDGE:-http://127.0.0.1:6688}"
FRESH_HOURS=24

phone_staged=0
if [ -n "${AUDIT_STAGED_FILES:-}" ]; then
  while IFS= read -r f; do
    case "$f" in
      nix/hosts/mandragora-phone/app/*/build/*) ;;
      nix/hosts/mandragora-phone/*) phone_staged=1 ;;
    esac
  done < <(audit_changed_files)
  if [ "$phone_staged" -eq 0 ]; then
    audit_pass "$CHECK" "no phone host files staged"
    exit 0
  fi
fi

report=$(python3 - "$BRIDGE" "$FRESH_HOURS" <<'PY'
import json
import sys
import urllib.request

base, fresh_hours = sys.argv[1], float(sys.argv[2])
try:
    with urllib.request.urlopen(base + "/api/phone/audit", timeout=4) as response:
        doc = json.load(response)
except (OSError, ValueError):
    print("unreachable")
    sys.exit(0)
if doc.get("ts") is None:
    print("none")
    sys.exit(0)
checks = [c for c in doc.get("checks", []) if isinstance(c, dict)]
bad = [c for c in checks if c.get("ok") is False]
age = (doc.get("age") or 0) / 3600
print(f"{'stale' if age > fresh_hours else 'fresh'} {age:.1f} {len(bad)} {len(checks)}")
for c in bad:
    print(f"{c.get('label', '')}: {c.get('detail', '')}")
PY
)

head=$(printf '%s\n' "$report" | head -n 1)
case "$head" in
  unreachable|"")
    audit_yellow "    phone-bridge did not answer at $BRIDGE; the phone's own checks were not read" >&2
    echo >&2
    audit_pass "$CHECK" "skipped (phone-bridge unreachable)"
    exit 0
    ;;
  none)
    audit_pass "$CHECK" "the phone has not reported yet"
    exit 0
    ;;
esac

read -r state age bad total <<< "$head"
details=$(printf '%s\n' "$report" | tail -n +2)

if [ "$bad" -eq 0 ]; then
  audit_pass "$CHECK" "all $total phone checks in place (reported $age h ago)"
  exit 0
fi

if [ "$phone_staged" -eq 1 ] && [ "$state" = fresh ]; then
  audit_fail "$CHECK" "$bad of $total phone checks are off (reported $age h ago)"
  printf '%s\n' "$details" | sed 's/^/    /' >&2
  echo "    this commit touches the phone host; fix them on the phone (settings → this phone) first" >&2
  exit 1
fi

audit_yellow "    $bad of $total phone checks are off (reported $age h ago, $state):" >&2
echo >&2
printf '%s\n' "$details" | sed 's/^/      /' >&2
audit_pass "$CHECK" "warned only; it fails commits that touch the phone host"
