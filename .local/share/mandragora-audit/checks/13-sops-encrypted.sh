set -uo pipefail
. "$AUDIT_HOME/lib/common.sh"

CHECK="${AUDIT_NAME:-sops-encrypted}"

SECRETS="$MANDRAGORA_REPO/secrets"
if [ ! -d "$SECRETS" ]; then
  audit_pass "$CHECK" "no secrets/ in repo; skipped"
  exit 0
fi

if ! command -v sops >/dev/null 2>&1; then
  audit_pass "$CHECK" "sops not on PATH; skipped"
  exit 0
fi

violations=0

while IFS= read -r rel; do
  [ -z "$rel" ] && continue
  case "$rel" in secrets/*) ;; *) continue ;; esac
  path="$MANDRAGORA_REPO/$rel"
  [ -f "$path" ] || continue

  case "$rel" in
    *.yaml|*.yml|*.json)
      status=$(sops filestatus "$path" 2>/dev/null | jq -r '.encrypted // "error"' 2>/dev/null)
      if [ "$status" != "true" ]; then
        audit_fail "$CHECK" "tracked file under secrets/ is not sops-encrypted: $rel"
        violations=$((violations + 1))
      fi
      ;;
  esac

  if grep -qE 'AGE-SECRET-KEY-|BEGIN [A-Z ]*PRIVATE KEY' "$path" 2>/dev/null; then
    audit_fail "$CHECK" "raw private key material in tracked file: $rel"
    violations=$((violations + 1))
  fi
done < <(audit_changed_files)

if [ "$violations" -gt 0 ]; then
  echo "  Everything committed under secrets/ must be sops ciphertext." >&2
  echo "  Encrypt with:  sops --config .sops.yaml encrypt --in-place <file>" >&2
  echo "  VPS runtime secrets are captured via nix/hosts/mandragora-vps/sync-env.sh --pull" >&2
  exit 1
fi

audit_pass "$CHECK"
