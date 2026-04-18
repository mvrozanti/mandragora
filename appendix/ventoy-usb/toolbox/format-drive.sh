#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Mandragora Drive Setup
# =============================================================================
# Partitions, formats, creates Btrfs subvolumes, mounts everything at /mnt
# ready for nixos-install. Copies the flake from USB if available.
#
# Usage: sudo ./format-drive.sh /dev/nvme0n1
#        sudo ./format-drive.sh /dev/sda
# =============================================================================

DRIVE="${1:-}"
BTRFS_OPTS="compress=zstd:1,noatime,ssd,space_cache=v2"

log()  { echo "[*] $1"; }
warn() { echo "[!] $1"; }
err()  { echo "[!!] $1" >&2; exit 1; }

[[ $EUID -ne 0 ]] && err "Must run as root."

if [[ -z "$DRIVE" ]]; then
    echo "Usage: $0 /dev/nvme0n1"
    echo ""
    echo "Available disks:"
    lsblk -d -o NAME,SIZE,MODEL,TRAN,RO | grep -v '^loop'
    echo ""
    echo "WARNING: This will DESTROY ALL DATA on the target drive."
    exit 1
fi

[[ ! -b "$DRIVE" ]] && err "$DRIVE is not a block device."

echo ""
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT "$DRIVE" 2>/dev/null || lsblk "$DRIVE"
echo ""
warn "ALL DATA on $DRIVE will be PERMANENTLY DESTROYED."
read -rp "Type YES to continue: " confirm
[[ "$confirm" != "YES" ]] && err "Aborted."

# ---- Partition naming: /dev/nvme0n1p1 vs /dev/sda1 ----
if [[ "$DRIVE" =~ nvme|loop ]]; then
    P="${DRIVE}p"
else
    P="${DRIVE}"
fi

# ---- Unmount anything on this drive ----
log "Unmounting existing partitions..."
umount -R /mnt 2>/dev/null || true
for part in "${P}"*; do
    [[ -b "$part" ]] && umount "$part" 2>/dev/null || true
done
swapoff "${P}3" 2>/dev/null || true

# ---- Partition ----
log "Partitioning $DRIVE (GPT: 4GB ESP + Btrfs + 32GB swap)..."
parted -s "$DRIVE" -- mklabel gpt
parted -s "$DRIVE" -- mkpart ESP fat32 1MB 4096MB
parted -s "$DRIVE" -- set 1 esp on
parted -s "$DRIVE" -- mkpart NIXOS btrfs 4096MB -32GB
parted -s "$DRIVE" -- mkpart SWAP linux-swap -32GB 100%
udevadm settle --timeout=5

# ---- Format ----
log "Formatting partitions..."
mkfs.fat -F 32 -n BOOT "${P}1"
mkfs.btrfs -f -L NIXOS "${P}2"
mkswap -L SWAP "${P}3"

# ---- Btrfs subvolumes ----
log "Creating Btrfs subvolumes..."
mount -t btrfs "${P}2" /mnt
btrfs subvolume create /mnt/root-blank
btrfs subvolume create /mnt/nix
btrfs subvolume create /mnt/persistent
btrfs subvolume snapshot /mnt/root-blank /mnt/root-active
umount /mnt

# ---- Mount everything for nixos-install ----
log "Mounting subvolumes at /mnt..."
mount -t btrfs -o "subvol=root-active,$BTRFS_OPTS" "${P}2" /mnt
mkdir -p /mnt/{nix,persistent,boot}
mount -t btrfs -o "subvol=nix,$BTRFS_OPTS"        "${P}2" /mnt/nix
mount -t btrfs -o "subvol=persistent,$BTRFS_OPTS"  "${P}2" /mnt/persistent
mount "${P}1" /mnt/boot
swapon "${P}3"

# ---- Persistent directory structure ----
log "Creating persistent directories..."
mkdir -p /mnt/persistent/{home/m,secrets}
mkdir -p /mnt/persistent/etc/{NetworkManager/system-connections,ssh}
mkdir -p /mnt/persistent/var/{lib/nixos,lib/bluetooth,lib/NetworkManager,log}

# ---- Copy flake from USB if available ----
FLAKE_SRC=""
for candidate in /mnt/ventoy/docs/mandragora-nixos /run/media/*/docs/mandragora-nixos; do
    if [[ -d "$candidate/hosts" ]]; then
        FLAKE_SRC="$candidate"
        break
    fi
done

if [[ -n "$FLAKE_SRC" ]]; then
    log "Copying Mandragora flake from USB..."
    mkdir -p /mnt/etc/nixos
    cp -a "$FLAKE_SRC" /mnt/etc/nixos/mandragora-nixos
    log "Flake at /mnt/etc/nixos/mandragora-nixos"
else
    warn "Flake not found on USB. Clone it manually:"
    warn "  git clone <repo-url> /mnt/etc/nixos/mandragora-nixos"
fi

# ---- Generate hardware config ----
log "Generating hardware-configuration.nix..."
HWCONF_DIR="/mnt/etc/nixos/mandragora-nixos/hosts/mandragora-desktop"
if [[ -d "$HWCONF_DIR" ]]; then
    nixos-generate-config --root /mnt --dir "$HWCONF_DIR" 2>/dev/null \
        && log "Hardware config written to $HWCONF_DIR" \
        || warn "nixos-generate-config failed. Run manually after install."
else
    nixos-generate-config --root /mnt 2>/dev/null \
        && log "Hardware config written to /mnt/etc/nixos/" \
        || warn "nixos-generate-config failed."
fi

# ---- Summary ----
echo ""
echo "══════════════════════════════════════════════════════"
echo "  DRIVE READY — everything mounted at /mnt"
echo "══════════════════════════════════════════════════════"
echo ""
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT "$DRIVE"
echo ""
echo "  NEXT STEPS:"
echo ""
echo "  1. Review hardware config:"
echo "     nvim /mnt/etc/nixos/mandragora-nixos/hosts/mandragora-desktop/hardware-configuration.nix"
echo ""
echo "  2. Install NixOS:"
echo "     nixos-install --flake /mnt/etc/nixos/mandragora-nixos#mandragora-desktop --no-root-passwd"
echo ""
echo "  3. Set passwords:"
echo "     nixos-enter --root /mnt -c 'passwd m'"
echo "     nixos-enter --root /mnt -c 'passwd'        # root (optional)"
echo ""
echo "  4. Reboot:"
echo "     umount -R /mnt && reboot"
echo ""
