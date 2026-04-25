#!/usr/bin/env bash
# Swap the live keyledsd.conf with the pywal-templated one and bounce the daemon.
set -u
src="$HOME/.cache/matugen/keyledsd.conf"
dst="$HOME/.config/keyledsd.conf"
[[ -f "$src" ]] || exit 0
mkdir -p "$(dirname "$dst")"
tmp="$(mktemp -p "$(dirname "$dst")" .keyledsd.XXXXXX)"
cp "$src" "$tmp"
chmod 644 "$tmp"
mv -f "$tmp" "$dst"
systemctl --user restart keyledsd 2>/dev/null || true
