# shellcheck shell=bash
set -uo pipefail
. "$AUDIT_HOME/lib/common.sh"

CHECK="${AUDIT_NAME:-vault-secrets}"

VAULT="${MANDRAGORA_VAULT:-$HOME/Documents/mandragora-desktop-obsidian-vault}"
if [ ! -d "$VAULT" ]; then
  audit_pass "$CHECK" "vault not present; skipped"
  exit 0
fi

ALLOWLIST=$(audit_load_allowlist "$AUDIT_HOME/allowlists/vault-secrets.txt")

PATTERNS=()
while IFS= read -r line; do
  [ -n "$line" ] && PATTERNS+=("$line")
done < <(grep -vE '^\s*(#|$)' "$AUDIT_HOME/lib/secret-patterns.txt")

violations=0

for entry in "${PATTERNS[@]}"; do
  name="${entry%%:*}"
  pattern="${entry#*:}"
  while IFS= read -r cite; do
    [ -z "$cite" ] && continue
    rel="${cite%:*}"
    if audit_in_allowlist "$cite" "$ALLOWLIST" || audit_in_allowlist "$rel" "$ALLOWLIST"; then
      continue
    fi
    audit_fail "$CHECK" "$name in published vault note: $cite"
    violations=$((violations + 1))
  done < <(grep -rnIE --exclude-dir=.git --exclude-dir=.obsidian --exclude-dir=.trash \
             --include='*.md' -e "$pattern" "$VAULT" 2>/dev/null \
           | sed -E "s|^${VAULT//|/\\|}/||" \
           | sed -E 's/^(.*\.md):([0-9]+):.*/\1:\2/')
done

if [ "$violations" -gt 0 ]; then
  echo "  The vault is served publicly at https://demo.mvr.ac and robots.txt allows indexing." >&2
  echo "  Notes describe mechanisms, incidents and threat models — never the material itself." >&2
  echo "  Remove the value, then rotate the credential: treat it as already compromised." >&2
  exit 1
fi

audit_pass "$CHECK"
