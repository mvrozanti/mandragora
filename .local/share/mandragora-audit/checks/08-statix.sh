set -uo pipefail
. "$AUDIT_HOME/lib/common.sh"

CHECK="${AUDIT_NAME:-statix}"

mapfile -t FILES < <(audit_changed_files | grep -E '\.nix$' || true)
[ "${#FILES[@]}" -eq 0 ] && { audit_pass "$CHECK" "no .nix changes"; exit 0; }

REPORTS=$(mktemp -d)
trap 'rm -rf "$REPORTS"' EXIT
for i in "${!FILES[@]}"; do
  [ -f "${FILES[$i]}" ] && printf '%s\0%s\0' "$i" "${FILES[$i]}"
done | xargs -0 -r -n2 -P"$(nproc)" bash -c 'statix check -o errfmt "$2" >"$0/$1" 2>/dev/null; exit 0' "$REPORTS"

violations=0
for i in "${!FILES[@]}"; do
  out=$(cat "$REPORTS/$i" 2>/dev/null)
  [ -n "$out" ] || continue
  printf '%s\n' "$out" | grep -q ':E:0:' && continue
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    audit_fail "$CHECK" "$line"
    violations=$((violations + 1))
  done <<< "$out"
done

if [ "$violations" -eq 0 ]; then
  audit_pass "$CHECK" "no antipatterns"
  exit 0
fi
echo "    statix antipatterns above. Auto-fix most with: statix fix <file>" >&2
exit 1
