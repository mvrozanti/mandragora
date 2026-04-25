#!/usr/bin/env bash
# Swap the live keyledsd.conf with the pywal-templated one and bounce the daemon.
set -u
src="$HOME/.cache/matugen/keyledsd.conf"
dst="$HOME/.config/keyledsd.conf"
[[ -f "$src" ]] || exit 0
install -Dm644 "$src" "$dst"
systemctl --user restart keyledsd 2>/dev/null || true
