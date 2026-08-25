#!/usr/bin/env bash
set -euo pipefail

KEY_FILE="/mnt/persistent/secrets/keys.txt"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOPS_YAML="$REPO_DIR/.sops.yaml"
SECRETS_FILE="$REPO_DIR/secrets/secrets.yaml"

for tool in age-keygen sops openssl; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "Missing: $tool — run: nix shell nixpkgs#age nixpkgs#sops"
    exit 1
  }
done

FORCE="${MANDRAGORA_BOOTSTRAP_FORCE:-0}"
if [ "$FORCE" != "1" ]; then
  for existing in "$SOPS_YAML" "$SECRETS_FILE"; do
    if [ -f "$existing" ]; then
      echo "Refusing to clobber $existing" >&2
      echo "" >&2
      echo "This script is FIRST-INSTALL ONLY. It rewrites .sops.yaml with a single" >&2
      echo "recipient and replaces secrets.yaml with a fresh one-key file, which on an" >&2
      echo "established system destroys every other recipient and every stored secret." >&2
      echo "" >&2
      echo "To add a recipient to an existing install, edit .sops.yaml and run" >&2
      echo "'sops updatekeys' on each file under secrets/ instead." >&2
      echo "" >&2
      echo "Override with MANDRAGORA_BOOTSTRAP_FORCE=1 only on a genuinely new machine." >&2
      exit 1
    fi
  done
fi

if [ ! -f "$KEY_FILE" ]; then
  echo "Generating age key..."
  age-keygen -o "$KEY_FILE"
  chmod 600 "$KEY_FILE"
else
  echo "Key already exists at $KEY_FILE — skipping generation."
fi

AGE_PUBKEY=$(grep "^# public key:" "$KEY_FILE" | awk '{print $NF}')
echo "Age public key: $AGE_PUBKEY"

cat > "$SOPS_YAML" <<EOF
keys:
  - &mandragora $AGE_PUBKEY
creation_rules:
  - path_regex: secrets/.*\\.yaml\$
    key_groups:
      - age:
          - *mandragora
EOF

mkdir -p "$(dirname "$SECRETS_FILE")"

echo ""
echo "Enter password for user m (you will be prompted twice):"
HASHED=$(openssl passwd -6)

PLAIN_FILE=$(mktemp)
cat > "$PLAIN_FILE" <<EOF
user:
    password: "$HASHED"
EOF

sops --encrypt --config "$SOPS_YAML" --input-type yaml --output-type yaml "$PLAIN_FILE" > "$SECRETS_FILE"
rm "$PLAIN_FILE"

echo ""
echo "Encrypted secrets written to $SECRETS_FILE"
echo "CRITICAL: $KEY_FILE must be backed up — losing it locks you out of all secrets."
echo ""
echo "Proceed with: sudo bash docs/install/install.sh"
