#!/bin/sh
# Mandragora USB — sh-compatible profile.d fallback.
# Main setup lives in /root/.zshrc (zsh is the live shell for root).
# This file only runs if the shell is NOT zsh (e.g. su, scripts).
case "$SHELL" in
    */zsh) return 0 ;;  # zsh handles it via .zshrc
esac

# Minimal setup for non-zsh shells
mountpoint -q /mnt/ventoy 2>/dev/null || mount -L Ventoy /mnt/ventoy 2>/dev/null || true
alias ll='ls -lah --color=auto' 2>/dev/null || true
echo "[MANDRAGORA] run 'zsh' for the full environment"
