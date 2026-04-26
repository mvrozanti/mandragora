#!/bin/bash
set -euo pipefail

# =============================================================================
# Mandragora Ventoy Multiboot USB Creator
# =============================================================================
# Expects pre-built ISOs in ~/iso_cache/ (run build-iso.sh first).
# Falls back to downloading stock ISOs if custom ones aren't found.
#
# Usage: sudo ./create-ventoy-usb.sh /dev/sdX
# =============================================================================

USB_DEV="${1:-}"
ARCH_PERSIST_MB=2048
NIXOS_PERSIST_MB=2048
VENTOY_VERSION="${VENTOY_VERSION:-1.1.10}"
LOCAL_CACHE="${LOCAL_CACHE:-$HOME/iso_cache}"
WORK_DIR="/tmp/ventoy_work"
MOUNT_POINT="/tmp/ventoy_usb"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

log()  { echo "[*] $1"; }
warn() { echo "[!] $1"; }
err()  { echo "[!!] $1" >&2; exit 1; }

cleanup() {
    umount "$MOUNT_POINT" 2>/dev/null || true
    [[ -d "$MOUNT_POINT" ]] && rmdir "$MOUNT_POINT" 2>/dev/null || true
}
trap cleanup EXIT

# ---- Preflight ----
[[ $EUID -ne 0 ]] && err "Must run as root."

if [[ -z "$USB_DEV" ]]; then
    echo "Usage: $0 /dev/sdX"
    echo ""
    echo "Removable devices:"
    lsblk -d -o NAME,SIZE,MODEL,TRAN,RM | awk 'NR==1 || $5=="1"'
    err "No device specified."
fi

[[ ! -b "$USB_DEV" ]] && err "$USB_DEV is not a block device."

DEV_NAME="$(basename "$USB_DEV")"
if [[ -f "/sys/block/$DEV_NAME/removable" ]] && [[ "$(cat "/sys/block/$DEV_NAME/removable")" != "1" ]]; then
    err "$USB_DEV is NOT removable. Refusing."
fi

echo ""
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MODEL "$USB_DEV" 2>/dev/null || lsblk "$USB_DEV"
echo ""
log "All data on $USB_DEV will be destroyed."
read -rp "Type YES to continue: " confirm
[[ "$confirm" != "YES" ]] && err "Aborted."

# ---- Check ISOs exist ----
mkdir -p "$LOCAL_CACHE"
ARCH_ISO="$LOCAL_CACHE/mandragora-arch.iso"
NIXOS_ISO="$LOCAL_CACHE/mandragora.iso"

if [[ ! -f "$ARCH_ISO" ]] || [[ ! -f "$NIXOS_ISO" ]]; then
    warn "Custom ISOs not found in $LOCAL_CACHE."
    warn "Run: sudo ./build-iso.sh"
    echo ""
    read -rp "Download stock ISOs instead? (y/N): " dl
    if [[ "$dl" =~ ^[Yy]$ ]]; then
        ping -c1 -W5 archlinux.org &>/dev/null || err "No network."
        if [[ ! -f "$ARCH_ISO" ]]; then
            log "Downloading stock Arch ISO..."
            curl -L --retry 3 --progress-bar \
                -o "$ARCH_ISO" \
                "https://geo.mirror.pkgbuild.com/iso/latest/archlinux-x86_64.iso"
        fi
        if [[ ! -f "$NIXOS_ISO" ]]; then
            log "Downloading stock NixOS ISO..."
            curl -L --retry 3 --progress-bar \
                -o "$NIXOS_ISO" \
                "https://channels.nixos.org/nixos-25.05/latest-nixos-minimal-x86_64-linux.iso"
        fi
        warn "Stock ISOs have no pre-installed tools. You'll need to set up manually."
    else
        err "No ISOs available. Run build-iso.sh first."
    fi
fi

# ---- Ventoy install ----
log "Unmounting $USB_DEV..."
for part in "${USB_DEV}"*; do umount "$part" 2>/dev/null || true; done

mkdir -p "$WORK_DIR"

VENTOY_TAR="ventoy-${VENTOY_VERSION}-linux.tar.gz"
if [[ -f "$LOCAL_CACHE/$VENTOY_TAR" ]]; then
    log "Using cached Ventoy."
else
    log "Downloading Ventoy $VENTOY_VERSION..."
    curl -L --retry 3 --progress-bar \
        -o "$LOCAL_CACHE/$VENTOY_TAR" \
        "https://github.com/ventoy/Ventoy/releases/download/v${VENTOY_VERSION}/${VENTOY_TAR}"
fi

tar -xzf "$LOCAL_CACHE/$VENTOY_TAR" -C "$WORK_DIR"
(cd "$WORK_DIR/ventoy-${VENTOY_VERSION}" && ./Ventoy2Disk.sh -I "$USB_DEV")
udevadm settle --timeout=10

lsblk -no LABEL "${USB_DEV}"* 2>/dev/null | grep -q 'VTOYEFI' \
    || err "Ventoy install failed."

# ---- Mount data partition ----
DATA_PART=""
for part in "${USB_DEV}1" "${USB_DEV}2" "${USB_DEV}3"; do
    [[ -b "$part" ]] && [[ "$(lsblk -no FSTYPE "$part" 2>/dev/null)" == "exfat" ]] && { DATA_PART="$part"; break; }
done
[[ -z "$DATA_PART" ]] && err "exFAT partition not found."

mkdir -p "$MOUNT_POINT"
mount "$DATA_PART" "$MOUNT_POINT"
mkdir -p "$MOUNT_POINT"/{isos,persistence,ventoy,toolbox,docs,keys}

# ---- Copy ISOs ----
log "Copying Arch ISO..."
cp "$ARCH_ISO" "$MOUNT_POINT/isos/mandragora-arch.iso"
log "Copying NixOS ISO..."
cp "$NIXOS_ISO" "$MOUNT_POINT/isos/mandragora.iso"

# ---- Persistence ----
VENTOY_DIR="$WORK_DIR/ventoy-${VENTOY_VERSION}"

create_persist() {
    local mb="$1" label="$2" dest="$3"
    [[ -f "$dest" ]] && return
    log "Creating ${mb}MB persistence: $(basename "$dest") (label: $label)..."
    (cd "$VENTOY_DIR" && bash CreatePersistentImg.sh -s "$mb" -l "$label" -o "$dest")
}

create_persist "$ARCH_PERSIST_MB"  "vtoycow"     "$MOUNT_POINT/persistence/arch_persistence.dat"
create_persist "$NIXOS_PERSIST_MB" "persistence" "$MOUNT_POINT/persistence/nixos_persistence.dat"

# ---- Config + toolbox ----
cp "$SCRIPT_DIR/ventoy.json" "$MOUNT_POINT/ventoy/ventoy.json"
cp "$SCRIPT_DIR/toolbox/"*.sh "$MOUNT_POINT/toolbox/"
chmod +x "$MOUNT_POINT/toolbox/"*.sh

# ---- Copy mandragora repo ----
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
if [[ -f "$REPO_DIR/flake.nix" || -d "$REPO_DIR/hosts" ]]; then
    log "Copying Mandragora NixOS repo to docs/..."
    rm -rf "$MOUNT_POINT/docs/mandragora"
    cp -r "$REPO_DIR" "$MOUNT_POINT/docs/mandragora"
else
    warn "Could not find mandragora repo at $REPO_DIR. Skipping repo copy."
fi

# ---- Done ----
sync
echo ""
echo "════════════════════════════════════════"
echo "  Mandragora USB — Ready"
echo "════════════════════════════════════════"
du -sh "$MOUNT_POINT/isos"        | awk '{print "  ISOs:        " $1}'
du -sh "$MOUNT_POINT/persistence" | awk '{print "  Persistence: " $1}'
[[ -d "$MOUNT_POINT/docs/mandragora" ]] && \
    du -sh "$MOUNT_POINT/docs/mandragora" | awk '{print "  Flake repo:  " $1}'
df -h "$MOUNT_POINT" | awk 'NR==2{print "  Free:        " $4}'
echo ""

umount "$MOUNT_POINT"
rmdir "$MOUNT_POINT" 2>/dev/null || true
rm -rf "$WORK_DIR"

echo "  Boot → Ventoy menu → pick Arch or NixOS."
echo "  Both have tools pre-installed, Ventoy auto-mounted."
echo ""
