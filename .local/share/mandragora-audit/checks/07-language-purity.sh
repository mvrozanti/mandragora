set -uo pipefail
. "$AUDIT_HOME/lib/common.sh"

CHECK="${AUDIT_NAME:-language-purity}"
ALLOWLIST=$(audit_load_allowlist "$AUDIT_HOME/allowlists/language-purity.txt")

# Rule 2 (language purity): non-Nix code (shell/Python/CSS/Lua) and config
# strings must live in XDG-mirrored files loaded via builtins.readFile or a
# pkgs.writeShellScript wrapper. They must NOT be embedded inline in a `.nix`
# file as an indented `''` heredoc (or a double-quoted extraConfig string).
#
# Maximal coverage: every inline `''` block is flagged EXCEPT the carve-outs
# Rule 2 explicitly permits:
#   - derivation build phases (installPhase/buildPhase/... , shellHook) — Nix
#     packaging idiom, no XDG home exists.
#   - writeShellScript* / writeShellApplication / writeScriptBin wrapper bodies
#     — Rule 2 names writeShellScript as a sanctioned mechanism.
#   - pure-metadata attrs (description/longDescription/meta/message/name/summary)
#     — prose, not code.
#
# Pre-existing violations are grandfathered in allowlists/language-purity.txt
# (entries are `path` for a whole-file exemption or `path:line` for one block).
# Regenerate that cache after a burn-down with:
#   AUDIT_EMIT_ALLOWLIST=1 mandragora-audit --check language-purity \
#     > "$AUDIT_HOME/allowlists/language-purity.txt"

scan() {
  [ "$#" -gt 0 ] || return 0
  gawk '
    function emit(n) { print FILENAME ":" n }
    FNR == 1 { lastWrap = -100 }
    /write(ShellScriptBin|ShellScript|ShellApplication|ScriptBin)/ { lastWrap = FNR }
    /^[[:space:]]*extraConfig[[:space:]]*=[[:space:]]*"/ { emit(FNR); next }
    {
      if (match($0, /([A-Za-z0-9_]+)[[:space:]]*=[[:space:]]*'\'\''[[:space:]]*$/, m)) {
        attr = m[1]
        if (attr ~ /^((pre|post)?(unpack|patch|configure|build|check|install|fixup|dist)Phase|installCheckPhase|shellHook|(pre|post)(Unpack|Patch|Configure|Build|Check|Install|Fixup))$/) next
        if (attr ~ /^(description|longDescription|meta|message|name|summary)$/) next
        if (FNR - lastWrap <= 8) next
        emit(FNR)
      }
    }
  ' "$@"
}

if [ -n "${AUDIT_EMIT_ALLOWLIST:-}" ]; then
  echo "# Pre-existing inline non-Nix blocks at audit landing time (Rule 2)."
  echo "# Each entry is path:line from repo root, or a bare path for the whole file."
  echo "# Migrate to .config/<app>/ + builtins.readFile, then drop the line."
  mapfile -t ALLF < <(git ls-files '*.nix')
  scan "${ALLF[@]}" 2>/dev/null | sort -u
  exit 0
fi

mapfile -t FILES < <(audit_changed_files | grep -E '\.nix$' || true)
[ "${#FILES[@]}" -eq 0 ] && { audit_pass "$CHECK" "no .nix changes"; exit 0; }

mapfile -t HITS < <(scan "${FILES[@]}" 2>/dev/null)

violations=0
for hit in "${HITS[@]}"; do
  [ -n "$hit" ] || continue
  file=${hit%%:*}
  if audit_in_allowlist "$hit" "$ALLOWLIST" || audit_in_allowlist "$file" "$ALLOWLIST"; then
    continue
  fi
  audit_fail "$CHECK" "$hit"
  violations=$((violations + 1))
done

if [ "$violations" -eq 0 ]; then
  audit_pass "$CHECK" "no new inline non-Nix blocks"
  exit 0
fi
echo "    Rule 2: move the body to a real file under .config/<app>/ (or snippets/)" >&2
echo "    and load it via builtins.readFile, or wrap it with pkgs.writeShellScript." >&2
echo "    Grandfather an intentional exception in allowlists/language-purity.txt." >&2
exit 1
