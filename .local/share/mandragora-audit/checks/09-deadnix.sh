set -uo pipefail
. "$AUDIT_HOME/lib/common.sh"

CHECK="${AUDIT_NAME:-deadnix}"

# deadnix: dead-code scan for Nix (unused let bindings / lambda args). Scoped
# to changed .nix files so pre-existing findings in untouched files never
# block. Auto-remove with: deadnix --edit <file>

mapfile -t FILES < <(audit_changed_files | grep -E '\.nix$' || true)
existing=()
for f in "${FILES[@]}"; do [ -f "$f" ] && existing+=("$f"); done
[ "${#existing[@]}" -eq 0 ] && { audit_pass "$CHECK" "no .nix changes"; exit 0; }

report=$(deadnix --fail "${existing[@]}" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
  audit_pass "$CHECK" "no dead code"
  exit 0
fi

printf '%s\n' "$report" | sed -E 's/\x1b\[[0-9;]*m//g' >&2
audit_fail "$CHECK" "dead code found (see above); auto-remove with: deadnix --edit"
exit 1
