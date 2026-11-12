# shellcheck shell=bash
set -uo pipefail
. "$AUDIT_HOME/lib/common.sh"

CHECK="${AUDIT_NAME:-private-names}"
ALLOWLIST=$(audit_load_allowlist "$AUDIT_HOME/allowlists/hub-tile.txt")
COMPOSE_DIR="$MANDRAGORA_REPO/nix/hosts/mandragora-vps/compose"
HUB_STATIC="$COMPOSE_DIR/hub/static"
VPS="${MANDRAGORA_VPS_SSH:-opc@100.84.78.83}"
TERMS_FILE="${MANDRAGORA_PRIVATE_TERMS:-${XDG_CONFIG_HOME:-$HOME/.config}/mandragora/private-terms}"

staged_added() {
  git -C "$MANDRAGORA_REPO" diff --cached --name-only --diff-filter=ACMR 2>/dev/null
  git -C "$MANDRAGORA_REPO" diff --cached -U0 --diff-filter=ACMR 2>/dev/null | grep -E '^\+' | grep -v '^+++' || true
}

terms=$(grep -vE '^[[:space:]]*(#|$)' "$TERMS_FILE" 2>/dev/null || true)
if [ -n "$terms" ]; then
  term_hits=""
  if staged_added | grep -qiE -f <(printf '%s\n' "$terms"); then
    term_hits="$term_hits staged-changes"
  fi
  if [ -n "${COMMIT_MSG_FILE:-}" ] && [ -f "$COMMIT_MSG_FILE" ] \
    && grep -qiE -f <(printf '%s\n' "$terms") "$COMMIT_MSG_FILE"; then
    term_hits="$term_hits commit-message"
  fi
  if [ -n "$term_hits" ]; then
    audit_fail "$CHECK" "a term from the local private list is named in:$term_hits"
    echo "    The repo is public. $TERMS_FILE lists patterns that must never be committed." >&2
    echo "    Reword the change so it does not name them." >&2
    exit 1
  fi
fi

if [ ! -d "$COMPOSE_DIR" ]; then
  audit_pass "$CHECK" "no compose dir; skipped"
  exit 0
fi

declared_subs() {
  {
    grep -rEho 'https://[a-z0-9-]+\.\$\{MVR_AC[^}]+\}|https://\$\{[A-Z_]+:-[a-z0-9-]+\.mvr\.ac\}' "$COMPOSE_DIR" 2>/dev/null \
      | sed -E -e 's#https://([a-z0-9-]+)\.\$\{MVR_AC.*#\1#' -e 's#https://\$\{[A-Z_]+:-([a-z0-9-]+)\.mvr\.ac\}#\1#'
    grep -Eo 'https://[a-z0-9-]+\.mvr\.ac' "$HUB_STATIC/index.html" "$HUB_STATIC/services.json" 2>/dev/null | sed -E 's#.*https://([a-z0-9-]+)\.mvr\.ac#\1#'
    python3 -c '
import json, sys
try:
    doc = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
for svc in doc.get("services", []):
    h = svc.get("host", "")
    if h.endswith(".mvr.ac"): print(h[:-7])
' "$HUB_STATIC/services.json" 2>/dev/null
    printf '%s\n' "$ALLOWLIST"
  } | sed '/^$/d' | sort -u
}

live_subs() {
  timeout 20 ssh -o BatchMode=yes -o ConnectTimeout=8 "$VPS" \
    'docker exec seafile-caddy curl -s --max-time 8 http://localhost:2019/config/' 2>/dev/null \
    | grep -oE '"[a-z0-9-]+\.mvr\.ac"' | tr -d '"' | sed -E 's#\.mvr\.ac$##' | sort -u
}

live=$(live_subs)
if [ -z "$live" ]; then
  audit_yellow "    live caddy unreachable ($VPS); private names not checked" >&2
  echo >&2
  audit_pass "$CHECK" "skipped (VPS unreachable)"
  exit 0
fi

private=$(comm -23 <(printf '%s\n' "$live") <(declared_subs))
if [ -z "$private" ]; then
  audit_pass "$CHECK" "no served host is undeclared"
  exit 0
fi

pattern=$(printf '%s\n' "$private" | sed -E 's#[.[\*^$]#\\&#g' | paste -sd'|' -)
hits=""
staged=$(git -C "$MANDRAGORA_REPO" diff --cached -U0 --diff-filter=ACMR 2>/dev/null | grep -E '^\+' | grep -v '^+++' || true)
if printf '%s\n' "$staged" | grep -qE "(^|[^a-z0-9-])($pattern)([^a-z0-9-]|$)"; then
  hits="$hits staged-changes"
fi
if [ -n "${COMMIT_MSG_FILE:-}" ] && [ -f "$COMMIT_MSG_FILE" ] \
  && grep -qE "(^|[^a-z0-9-])($pattern)([^a-z0-9-]|$)" "$COMMIT_MSG_FILE"; then
  hits="$hits commit-message"
fi

if [ -n "$hits" ]; then
  audit_fail "$CHECK" "a served host that the repo never declared is named in:$hits"
  echo "    The repo is public. A host that is served but undeclared is private by definition;" >&2
  echo "    it is listed on the hub automatically and must not appear in any commit." >&2
  echo "    Declare it on purpose (compose + tile) or keep its name out." >&2
  exit 1
fi
audit_pass "$CHECK" "$(printf '%s\n' "$private" | wc -l) undeclared served host(s); none named in this commit"
