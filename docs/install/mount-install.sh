#!/usr/bin/env bash
set -euo pipefail

OPTS="compress=zstd:1,noatime,ssd,space_cache=v2"

mount -t btrfs -o "subvol=root-active,$OPTS" /dev/disk/by-label/NIXOS /mnt

mkdir -p /mnt/{boot,nix,persistent}

mount -t btrfs -o "subvol=nix,$OPTS"        /dev/disk/by-label/NIXOS /mnt/nix
mount -t btrfs -o "subvol=persistent,$OPTS" /dev/disk/by-label/NIXOS /mnt/persistent
mount -o fmask=0022,dmask=0022 /dev/disk/by-label/BOOT /mnt/boot

swapon /dev/disk/by-label/SWAP

mkdir -p \
  /mnt/persistent/home/m \
  /mnt/persistent/secrets \
  /mnt/persistent/var/log \
  /mnt/persistent/var/lib/nixos \
  /mnt/persistent/var/lib/systemd/coredump \
  "/mnt/persistent/etc/NetworkManager/system-connections"

touch /mnt/persistent/etc/machine-id

echo "Mounted. Run: sudo bash docs/install/bootstrap-age-key.sh"
