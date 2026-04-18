#!/usr/bin/env bash
set -euo pipefail

KEY_FILE="/mnt/persistent/secrets/keys.txt"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOPS_YAML="$REPO_DIR/.sops.yaml"
SECRETS_FILE="$REPO_DIR/secrets/secrets.yaml"

for tool in age-keygen sops openssl; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "Missing: $tool — run: nix shell nixpkgs#age nixpkgs#sops"
    exit 1
  }
done

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
echo "Proceed with: sudo bash snippets/install.sh"
