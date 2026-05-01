set -uo pipefail
. "$AUDIT_HOME/lib/common.sh"

CHECK="${AUDIT_NAME:-no-extraconfig}"
ALLOWLIST=$(audit_load_allowlist "$AUDIT_HOME/allowlists/no-extraconfig.txt")

# Rule 2: never embed config strings inside .nix files via extraConfig blocks.
# Pattern: `extraConfig =` followed (possibly across whitespace/newlines) by `''`.
# We restrict to .nix files. Allowlist entries are file paths from repo root.

mapfile -t HITS < <(
  audit_changed_files \
    | grep -E '\.nix$' \
    | xargs -r grep -nP "extraConfig\s*=\s*''" 2>/dev/null
)

violations=0
for hit in "${HITS[@]}"; do
  file=${hit%%:*}
  if audit_in_allowlist "$file" "$ALLOWLIST"; then continue; fi
  audit_fail "$CHECK" "$hit"
  violations=$((violations + 1))
done

if [ "$violations" -eq 0 ]; then
  audit_pass "$CHECK" "no new extraConfig string blocks"
  exit 0
fi
echo "    Rule 2: move the body to a real file under .config/<app>/ and load it via" >&2
echo "    builtins.readFile. Allowlist (pre-existing): allowlists/no-extraconfig.txt." >&2
exit 1
