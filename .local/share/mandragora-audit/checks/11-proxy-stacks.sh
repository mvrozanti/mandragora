set -uo pipefail
. "$AUDIT_HOME/lib/common.sh"

CHECK="${AUDIT_NAME:-proxy-stacks}"

GENERATOR="$MANDRAGORA_REPO/nix/hosts/mandragora-vps/compose/generate-proxy-stacks.py"
MANIFEST="$MANDRAGORA_REPO/nix/hosts/mandragora-vps/compose/proxy-stacks.json"

if [ ! -f "$GENERATOR" ] || [ ! -f "$MANIFEST" ]; then
  audit_pass "$CHECK" "proxy-stacks generator or manifest missing; skipped"
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  audit_pass "$CHECK" "python3 unavailable; skipped"
  exit 0
fi

out=$(python3 "$GENERATOR" --check 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
  audit_pass "$CHECK" "generated proxy compose files match the manifest"
  exit 0
fi

printf '%s\n' "$out" | sed 's/^/    /' >&2
audit_fail "$CHECK" "hand-edited proxy compose file; run the generator: nix/hosts/mandragora-vps/compose/generate-proxy-stacks.py"
exit 1
