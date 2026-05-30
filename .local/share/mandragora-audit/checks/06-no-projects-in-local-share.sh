set -uo pipefail
. "$AUDIT_HOME/lib/common.sh"

CHECK="${AUDIT_NAME:-no-projects-in-local-share}"
ALLOWLIST=$(audit_load_allowlist "$AUDIT_HOME/allowlists/local-share-projects.txt")

SHARE="$MANDRAGORA_REPO/.local/share"
if [ ! -d "$SHARE" ]; then
  audit_pass "$CHECK" "no .local/share/ in repo; skipped"
  exit 0
fi

violations=0
while IFS= read -r path; do
  [ -z "$path" ] && continue
  rel="${path#"$SHARE"/}"
  top="${rel%%/*}"
  if audit_in_allowlist "$top" "$ALLOWLIST"; then continue; fi
  audit_fail "$CHECK" "project marker under .local/share/: $rel"
  violations=$((violations + 1))
done < <(find "$SHARE" -mindepth 2 -maxdepth 4 \
  \( -name .git -o -name pyproject.toml -o -name Cargo.toml \
     -o -name package.json -o -name flake.nix \) -print 2>/dev/null)

if [ "$violations" -gt 0 ]; then
  echo "  .local/share/ is the XDG dotfiles mirror, not a project tree." >&2
  echo "  Move the project to ~/Projects/<name>/, or allowlist the top-level" >&2
  echo "  directory name in $AUDIT_HOME/allowlists/local-share-projects.txt" >&2
  exit 1
fi

audit_pass "$CHECK"
