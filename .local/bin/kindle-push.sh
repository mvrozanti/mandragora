#!/usr/bin/env bash
set -euo pipefail

KINDLE_HOST="${KINDLE_HOST:-100.80.53.92}"
KINDLE_PORT="${KINDLE_PORT:-22}"
REPO="${MANDRAGORA_REPO:-/etc/nixos/mandragora}"
SRC="$REPO/nix/hosts/mandragora-kindle"
PUBKEY="${KINDLE_PUBKEY:-$HOME/.ssh/id_ed25519.pub}"
M=/mnt/us/mandragora

SSH=(ssh -p "$KINDLE_PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 "root@$KINDLE_HOST")

[ -d "$SRC" ] || { echo "kindle-push: no payload at $SRC" >&2; exit 1; }
[ -f "$PUBKEY" ] || { echo "kindle-push: no public key at $PUBKEY" >&2; exit 1; }

put() {
  "${SSH[@]}" "mkdir -p $(dirname "$2") && cat > '$2' && chmod ${3:-755} '$2'" < "$1"
  echo "  $2"
}

echo "kindle-push: $KINDLE_HOST"
"${SSH[@]}" "mkdir -p $M/bin $M/rc $M/state $M/log $M/scriptlets $M/art $M/icons"

echo "rc:"
for f in "$SRC"/rc/*; do put "$f" "$M/rc/$(basename "$f")"; done
keys=$(mktemp)
cat "$PUBKEY" > "$keys"
for k in "$SRC"/rc/authorized_keys.d/*.pub; do [ -f "$k" ] && cat "$k" >> "$keys"; done
"${SSH[@]}" "cat > $M/rc/authorized_keys && chmod 600 $M/rc/authorized_keys" < "$keys"
echo "  $M/rc/authorized_keys ($(wc -l < "$keys") keys: $PUBKEY + repo)"
rm -f "$keys"

echo "scriptlets:"
for f in "$SRC"/scriptlets/*.sh; do
  put "$f" "$M/scriptlets/$(basename "$f")"
  "${SSH[@]}" "cp $M/scriptlets/$(basename "$f") /mnt/us/documents/"
done

echo "koreader plugin:"
"${SSH[@]}" "mkdir -p /mnt/us/koreader/plugins/mandragora.koplugin"
for f in "$SRC"/koplugin/mandragora.koplugin/*.lua; do
  put "$f" "/mnt/us/koreader/plugins/mandragora.koplugin/$(basename "$f")" 644
done

echo "boot job + services:"
"${SSH[@]}" "/bin/sh $M/rc/install.sh"

echo
echo "kindle-push: done. restart KOReader to pick up the plugin."
