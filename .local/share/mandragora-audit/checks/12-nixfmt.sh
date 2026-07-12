set -uo pipefail
. "$AUDIT_HOME/lib/common.sh"

CHECK="${AUDIT_NAME:-nixfmt}"

mapfile -t FILES < <(audit_changed_files | grep -E '\.nix$' || true)
existing=()
for f in "${FILES[@]}"; do [ -f "$f" ] && existing+=("$f"); done
[ "${#existing[@]}" -eq 0 ] && { audit_pass "$CHECK" "no .nix changes"; exit 0; }

if ! command -v nixfmt >/dev/null 2>&1; then
  audit_pass "$CHECK" "nixfmt unavailable; skipped"
  exit 0
fi

violations=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  audit_fail "$CHECK" "${line%%:*}"
  violations=$((violations + 1))
done < <(nixfmt --check "${existing[@]}" 2>&1 >/dev/null | grep -F ': not formatted')

if [ "$violations" -eq 0 ]; then
  audit_pass "$CHECK" "tree formatted (nixfmt-rfc-style)"
  exit 0
fi
echo "    unformatted .nix above. Fix with: nix fmt <file>  (or: nixfmt <file>)" >&2
exit 1
