#!/bin/bash
set -euo pipefail

# =============================================================================
# Build Mandragora custom ISOs (Arch + NixOS)
# =============================================================================
# Output: ~/iso_cache/mandragora-arch.iso, ~/iso_cache/mandragora-nixos.iso
# Requires: archiso (for Arch), nix (for NixOS). Builds whichever is possible.
# Usage: sudo ./build-iso.sh
# =============================================================================

ISO_CACHE="${ISO_CACHE:-$HOME/iso_cache}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

log()  { echo "[*] $1"; }
warn() { echo "[!] $1"; }
err()  { echo "[!!] $1" >&2; exit 1; }

[[ $EUID -ne 0 ]] && err "Must run as root."
mkdir -p "$ISO_CACHE"

# ======================== Arch ISO ========================
build_arch() {
    if ! command -v mkarchiso &>/dev/null; then
        warn "archiso not installed (pacman -S archiso). Skipping Arch ISO build."
        return 1
    fi

    local RELENG="/usr/share/archiso/configs/releng"
    [[ -d "$RELENG" ]] || { warn "releng profile not found. Skipping."; return 1; }

    log "Building custom Arch ISO..."
    local PROFILE="/tmp/mandragora-archiso-profile"
    local WORK="/tmp/mandragora-archiso-work"
    rm -rf "$PROFILE" "$WORK"
    cp -r "$RELENG" "$PROFILE"

    # merge packages
    grep -v '^#' "$SCRIPT_DIR/archiso/packages-extra.txt" | grep -v '^$' \
        >> "$PROFILE/packages.x86_64"
    sort -u "$PROFILE/packages.x86_64" -o "$PROFILE/packages.x86_64"

    # overlay airootfs
    cp -r "$SCRIPT_DIR/archiso/airootfs/." "$PROFILE/airootfs/"
    echo "mandragora-usb" > "$PROFILE/airootfs/etc/hostname"

    # patch profiledef
    sed -i 's/^iso_name=.*/iso_name="mandragora-arch"/' "$PROFILE/profiledef.sh"
    sed -i "s/^iso_label=.*/iso_label=\"MANDRAGORA_ARCH\"/" "$PROFILE/profiledef.sh"

    # file permissions for our script
    if ! grep -q "99-mandragora" "$PROFILE/profiledef.sh"; then
        sed -i 's|^\(file_permissions=(\)|\1\n  ["/etc/profile.d/99-mandragora.sh"]="0:0:755"|' \
            "$PROFILE/profiledef.sh"
    fi

    mkarchiso -v -w "$WORK" -o "$ISO_CACHE" "$PROFILE"
    rm -rf "$PROFILE" "$WORK"

    # rename to stable name
    local BUILT
    BUILT=$(find "$ISO_CACHE" -maxdepth 1 -name "mandragora-arch-*.iso" 2>/dev/null | sort | tail -1)
    if [[ -n "$BUILT" ]]; then
        mv "$BUILT" "$ISO_CACHE/mandragora-arch.iso"
        log "Arch ISO: $ISO_CACHE/mandragora-arch.iso ($(du -sh "$ISO_CACHE/mandragora-arch.iso" | cut -f1))"
    else
        warn "Arch ISO build produced no output."
        return 1
    fi
}

# ======================== NixOS ISO ========================
# Prefer building a custom ISO via nix if available on the host.
# Falls back to downloading the stock NixOS minimal ISO — which is perfectly
# fine for installation and has nix-shell for anything else needed live.
# NOTE: do NOT install nix on your main machine just for this. Use the fallback.
build_nixos() {
    local NIXOS_CHANNEL="${NIXOS_CHANNEL:-25.05}"
    local DEST="$ISO_CACHE/mandragora-nixos.iso"

    # Custom build path (only if nix already exists on host)
    if command -v nix &>/dev/null; then
        log "Building custom NixOS ISO..."
        local NIXOS_DIR="$SCRIPT_DIR/nixos-iso"
        nix build "${NIXOS_DIR}#nixosConfigurations.mandragora-usb.config.system.build.isoImage" \
            --out-link /tmp/mandragora-nixos-result \
            --extra-experimental-features "nix-command flakes"
        local BUILT
        BUILT=$(find /tmp/mandragora-nixos-result/iso -name "*.iso" 2>/dev/null | head -1)
        if [[ -n "$BUILT" ]]; then
            cp "$BUILT" "$DEST"
            rm -f /tmp/mandragora-nixos-result
            log "NixOS ISO: $DEST ($(du -sh "$DEST" | cut -f1))"
            return 0
        fi
        warn "Custom NixOS build failed. Falling back to stock ISO download."
    else
        log "nix not on host. Downloading stock NixOS $NIXOS_CHANNEL minimal ISO..."
        log "(Stock ISO is fine for installation — nix-shell handles anything else live.)"
    fi

    # Stock download fallback
    local URL="https://channels.nixos.org/nixos-${NIXOS_CHANNEL}/latest-nixos-minimal-x86_64-linux.iso"
    curl -L --retry 3 --progress-bar -o "$DEST" "$URL" \
        || { warn "NixOS ISO download failed."; return 1; }
    [[ $(stat -c%s "$DEST") -gt 500000000 ]] \
        || { warn "NixOS ISO download too small — likely a bad URL or redirect."; return 1; }
    log "NixOS ISO: $DEST ($(du -sh "$DEST" | cut -f1))"
}

# ======================== Run ========================
ARCH_OK=false
NIXOS_OK=false

build_arch  && ARCH_OK=true
build_nixos && NIXOS_OK=true

echo ""
echo "════════════════════════════════════════"
echo "  Build results:"
$ARCH_OK  && echo "  Arch:  $ISO_CACHE/mandragora-arch.iso"  || echo "  Arch:  SKIPPED"
$NIXOS_OK && echo "  NixOS: $ISO_CACHE/mandragora-nixos.iso" || echo "  NixOS: SKIPPED"
echo "════════════════════════════════════════"

$ARCH_OK || $NIXOS_OK || err "No ISOs were built."
