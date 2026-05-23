set -uo pipefail
. "$AUDIT_HOME/lib/common.sh"

CHECK="${AUDIT_NAME:-hub-tile}"
ALLOWLIST=$(audit_load_allowlist "$AUDIT_HOME/allowlists/hub-tile.txt")

COMPOSE_DIR="$MANDRAGORA_REPO/nix/hosts/mandragora-vps/compose"
HUB_INDEX="$COMPOSE_DIR/hub/static/index.html"

if [ ! -d "$COMPOSE_DIR" ] || [ ! -f "$HUB_INDEX" ]; then
  audit_pass "$CHECK" "vps compose dir or hub index missing; skipped"
  exit 0
fi

extract_subs_from_compose() {
  grep -rEho 'https://[a-z0-9-]+\.\$\{MVR_AC[^}]+\}|https://\$\{[A-Z_]+:-[a-z0-9-]+\.mvr\.ac\}' "$COMPOSE_DIR" 2>/dev/null \
    | sed -E -e 's#https://([a-z0-9-]+)\.\$\{MVR_AC.*#\1#' \
             -e 's#https://\$\{[A-Z_]+:-([a-z0-9-]+)\.mvr\.ac\}#\1#' \
    | sort -u
}

extract_subs_from_hub() {
  grep -Eo 'https://[a-z0-9-]+\.mvr\.ac' "$HUB_INDEX" \
    | sed -E 's#https://([a-z0-9-]+)\.mvr\.ac#\1#' \
    | sort -u
}

declared_subs=$(extract_subs_from_compose)
tiled_subs=$(extract_subs_from_hub)

violations=0
while IFS= read -r sub; do
  [ -z "$sub" ] && continue
  if audit_in_allowlist "$sub" "$ALLOWLIST"; then continue; fi
  if ! printf '%s\n' "$tiled_subs" | grep -Fxq "$sub"; then
    audit_fail "$CHECK" "subdomain '$sub.mvr.ac' has no hub tile"
    violations=$((violations + 1))
  fi
done <<< "$declared_subs"

if [ "$violations" -eq 0 ]; then
  audit_pass "$CHECK" "every *.mvr.ac caddy host has a hub tile"
  exit 0
fi

echo "    Rule 16: add <a class=\"tile\"> entry in $HUB_INDEX." >&2
echo "    To intentionally skip a subdomain, add it to allowlists/hub-tile.txt." >&2
exit 1
