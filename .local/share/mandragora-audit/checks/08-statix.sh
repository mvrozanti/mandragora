set -uo pipefail
. "$AUDIT_HOME/lib/common.sh"

CHECK="${AUDIT_NAME:-statix}"

# statix: AST-based Nix antipattern lint (oppiliappan/statix). Scoped to
# changed .nix files so pre-existing findings in untouched files never block.
# Lint config (disabled rules) lives in statix.toml at the repo root.
# Most findings auto-fix with: statix fix <file>
#
# Unparseable files (substituteAll templates with @PLACEHOLDER@ markers) are
# skipped: statix reports them as severity E code 0, and syntax is already
# enforced by the build, not by this lint.

mapfile -t FILES < <(audit_changed_files | grep -E '\.nix$' || true)
[ "${#FILES[@]}" -eq 0 ] && { audit_pass "$CHECK" "no .nix changes"; exit 0; }

violations=0
for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue
  out=$(statix check -o errfmt "$f" 2>/dev/null || true)
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
