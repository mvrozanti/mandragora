set -uo pipefail
. "$AUDIT_HOME/lib/common.sh"

CHECK="${AUDIT_NAME:-hub-tile}"
ALLOWLIST=$(audit_load_allowlist "$AUDIT_HOME/allowlists/hub-tile.txt")

COMPOSE_DIR="$MANDRAGORA_REPO/nix/hosts/mandragora-vps/compose"
HUB_INDEX="$COMPOSE_DIR/hub/static/index.html"
VPS="${MANDRAGORA_VPS_SSH:-opc@100.84.78.83}"

if [ ! -d "$COMPOSE_DIR" ] || [ ! -f "$HUB_INDEX" ]; then
  audit_pass "$CHECK" "vps compose dir or hub index missing; skipped"
  exit 0
fi

subs_from_compose() {
  grep -rEho 'https://[a-z0-9-]+\.\$\{MVR_AC[^}]+\}|https://\$\{[A-Z_]+:-[a-z0-9-]+\.mvr\.ac\}' "$COMPOSE_DIR" 2>/dev/null \
    | sed -E -e 's#https://([a-z0-9-]+)\.\$\{MVR_AC.*#\1#' \
             -e 's#https://\$\{[A-Z_]+:-([a-z0-9-]+)\.mvr\.ac\}#\1#' \
    | sort -u
}

subs_from_hub_file() {
  grep -Eo 'https://[a-z0-9-]+\.mvr\.ac' "$1" | sed -E 's#https://([a-z0-9-]+)\.mvr\.ac#\1#' | sort -u
}

subs_from_live_caddy() {
  timeout 20 ssh -o BatchMode=yes -o ConnectTimeout=8 "$VPS" \
    'docker exec seafile-caddy curl -s --max-time 8 http://localhost:2019/config/' 2>/dev/null \
    | grep -oE '"[a-z0-9-]+\.mvr\.ac"' | tr -d '"' \
    | sed -E 's#([a-z0-9-]+)\.mvr\.ac#\1#' | sort -u
}

violations=0

report_missing() {
  local source_label="$1"; shift
  while IFS= read -r sub; do
    [ -z "$sub" ] && continue
    audit_in_allowlist "$sub" "$ALLOWLIST" && continue
    if ! printf '%s\n' "$tiled" | grep -Fxq "$sub"; then
      audit_fail "$CHECK" "$source_label serves '$sub.mvr.ac' but it has no hub tile"
      violations=$((violations + 1))
    fi
  done <<< "$1"
}

tiled=$(subs_from_hub_file "$HUB_INDEX")

report_missing "compose" "$(subs_from_compose)"

live_hosts=$(subs_from_live_caddy)
if [ -z "$live_hosts" ]; then
  audit_yellow "    live caddy unreachable ($VPS); repo-only check performed" >&2
  echo >&2
else
  report_missing "live caddy" "$live_hosts"

  live_hub=$(timeout 20 ssh -o BatchMode=yes -o ConnectTimeout=8 "$VPS" \
    'cat /home/opc/hub/static/index.html' 2>/dev/null)
  if [ -n "$live_hub" ]; then
    live_tiled=$(printf '%s' "$live_hub" | grep -Eo 'https://[a-z0-9-]+\.mvr\.ac' \
      | sed -E 's#https://([a-z0-9-]+)\.mvr\.ac#\1#' | sort -u)
    drift=$(comm -23 <(printf '%s\n' "$tiled") <(printf '%s\n' "$live_tiled"))
    if [ -n "$drift" ]; then
      audit_fail "$CHECK" "hub.mvr.ac is stale — tiles in the repo but not deployed: $(printf '%s' "$drift" | tr '\n' ' ')"
      echo "    Deploy it: rsync -a $COMPOSE_DIR/hub/static/index.html $VPS:/home/opc/hub/static/index.html" >&2
      violations=$((violations + 1))
    fi
  fi
fi

if [ "$violations" -eq 0 ]; then
  audit_pass "$CHECK" "every served *.mvr.ac host has a hub tile, and hub.mvr.ac is current"
  exit 0
fi

echo "    Rule 16: add <a class=\"tile\"> entry in $HUB_INDEX, then deploy the hub." >&2
echo "    To intentionally skip a subdomain, add it to allowlists/hub-tile.txt." >&2
exit 1
