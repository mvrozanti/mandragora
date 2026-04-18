#!/usr/bin/env bash
# Mandragora Drive Formatting Script (DANGEROUS)
# Run from the NixOS live USB

set -euo pipefail

DRIVE=$1

if [ -z "$DRIVE" ]; then
    echo "Usage: $0 /dev/nvme0n1"
    echo "WARNING: This will destroy all data on the target drive."
    exit 1
fi

echo "Formatting $DRIVE..."
parted "$DRIVE" -- mklabel gpt
parted "$DRIVE" -- mkpart ESP fat32 1MB 4096MB
parted "$DRIVE" -- set 1 esp on
parted "$DRIVE" -- mkpart NIXOS btrfs 4096MB -32GB
parted "$DRIVE" -- mkpart SWAP linux-swap -32GB 100%

mkfs.fat -F 32 -n BOOT "${DRIVE}p1"
mkfs.btrfs -f -L NIXOS "${DRIVE}p2"
mkswap -L SWAP "${DRIVE}p3"

mount -t btrfs "${DRIVE}p2" /mnt
btrfs subvolume create /mnt/root-blank
btrfs subvolume create /mnt/nix
btrfs subvolume create /mnt/persistent
btrfs subvolume snapshot /mnt/root-blank /mnt/root-active
umount /mnt

echo "Formatting complete. Proceed with mount and NixOS installation."
