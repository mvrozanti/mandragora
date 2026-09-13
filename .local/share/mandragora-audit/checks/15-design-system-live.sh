set -uo pipefail
. "$AUDIT_HOME/lib/common.sh"

CHECK="${AUDIT_NAME:-design-system-live}"

COMPOSE="$MANDRAGORA_REPO/nix/hosts/mandragora-vps/compose"
CANON_CSS="$COMPOSE/hub/static/theme.css"
CANON_JS="$COMPOSE/hub/static/theme.js"
ALLOWLIST="$MANDRAGORA_REPO/.local/share/mandragora-audit/allowlists/design-system-live.txt"

if [ ! -f "$CANON_CSS" ] || [ ! -f "$CANON_JS" ]; then
  audit_pass "$CHECK" "canonical hub/static/theme.{css,js} missing; skipped"
  exit 0
fi

allowed() {
  [ -f "$ALLOWLIST" ] || return 1
  grep -qxF "$1" "$ALLOWLIST" 2>/dev/null
}

canon_css_sum=$(md5sum <"$CANON_CSS" | cut -d' ' -f1)
canon_js_sum=$(md5sum <"$CANON_JS" | cut -d' ' -f1)

failures=0
while IFS= read -r css; do
  dir=$(dirname "$css")
  stack=$(printf '%s\n' "${css#"$COMPOSE"/}" | cut -d/ -f1)

  if allowed "$stack"; then
    continue
  fi

  if [ "$(md5sum <"$css" | cut -d' ' -f1)" != "$canon_css_sum" ]; then
    printf '    %s drifted from hub/static/theme.css\n' "${css#"$MANDRAGORA_REPO"/}" >&2
    failures=$((failures + 1))
  fi

  if [ ! -f "$dir/theme.js" ]; then
    printf '    %s ships theme.css but no theme.js: palette will not follow setbg\n' \
      "${dir#"$MANDRAGORA_REPO"/}" >&2
    failures=$((failures + 1))
    continue
  fi

  if [ "$(md5sum <"$dir/theme.js" | cut -d' ' -f1)" != "$canon_js_sum" ]; then
    printf '    %s/theme.js drifted from hub/static/theme.js\n' \
      "${dir#"$MANDRAGORA_REPO"/}" >&2
    failures=$((failures + 1))
  fi

  if ! grep -rqlF "theme.js" "$dir"/../ --include='*.html' --include='*.py' --include='*.conf' 2>/dev/null \
    && ! grep -rqlF "theme.js" "$dir" --include='*.html' 2>/dev/null; then
    printf '    %s never references theme.js: palette will not follow setbg\n' \
      "${dir#"$MANDRAGORA_REPO"/}" >&2
    failures=$((failures + 1))
  fi
done < <(find "$COMPOSE" -name theme.css -type f 2>/dev/null | sort)

if [ "$failures" -gt 0 ]; then
  audit_fail "$CHECK" "a served UI does not track the live matugen palette (AGENTS.md Rule 20)"
  exit 1
fi

audit_pass "$CHECK" "every served UI ships the canonical theme.css/theme.js and wires the palette endpoint"
exit 0
