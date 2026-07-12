#!/usr/bin/env bash

set -euo pipefail

POOL_LABEL="NIXOS"
ESP_LABEL="BOOT"
SWAP_LABEL="SWAP"

ESP_SIZE_MIB=1024
SWAP_SIZE_MIB=32768

MIN_BYTES=$(( 60 * 1024 * 1024 * 1024 ))
WARN_BYTES=$(( 120 * 1024 * 1024 * 1024 ))

BTRFS_SUBVOLUMES=(root-blank root-active nix persistent games)

log_info()  { printf '[info] %s\n' "$*" >&2; }
log_warn()  { printf '[warn] %s\n' "$*" >&2; }
log_error() { printf '[error] %s\n' "$*" >&2; }
die()       { log_error "$*"; exit 1; }

require_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        die "this command must run as root"
    fi
}

confirm_typed() {
    local expected="$1"
    local prompt="$2"
    local got
    log_info "$prompt"
    log_info "Type ${expected} to continue:"
    read -r got
    [[ "$got" == "$expected" ]] || die "got '$got', expected '$expected' — aborting."
}

partition_suffix() {
    local disk="$1" index="$2"
    if [[ "$disk" =~ nvme || "$disk" =~ mmcblk || "$disk" =~ loop ]]; then
        printf '%sp%s' "$disk" "$index"
    else
        printf '%s%s' "$disk" "$index"
    fi
}

check_size() {
    local bytes="$1"
    if (( bytes < MIN_BYTES )); then
        die "disk too small: $(numfmt --to=iec "$bytes") (minimum 60 GiB)"
    fi
    if (( bytes < WARN_BYTES )); then
        log_warn "disk is small: $(numfmt --to=iec "$bytes") (recommended >= 120 GiB)"
    fi
}

refuse_if_mounted() {
    local disk="$1"
    local mounted
    mounted=$(lsblk -nro NAME,MOUNTPOINT "$disk" | awk 'NF == 2 {print}')
    if [[ -n "$mounted" ]]; then
        log_error "$disk has mounted partitions:"
        echo "$mounted" >&2
        die "unmount everything on $disk before formatting"
    fi
}

warn_existing_partitions() {
    local disk="$1"
    local parts
    parts=$(lsblk -nro NAME,TYPE,SIZE "$disk" | awk '$2 == "part" {print}')
    if [[ -n "$parts" ]]; then
        log_warn "$disk has existing partitions:"
        echo "$parts" >&2
    fi
}

partition_disk() {
    local disk="$1"
    log_info "Partitioning $disk (ESP ${ESP_SIZE_MIB}MiB, SWAP ${SWAP_SIZE_MIB}MiB, Btrfs pool = rest)..."
    sgdisk --zap-all "$disk"
    sgdisk -n "1:0:+${ESP_SIZE_MIB}M"  -t 1:ef00 -c 1:"$ESP_LABEL"  "$disk"
    sgdisk -n "2:0:+${SWAP_SIZE_MIB}M" -t 2:8200 -c 2:"$SWAP_LABEL" "$disk"
    sgdisk -n "3:0:0"                  -t 3:8300 -c 3:"$POOL_LABEL" "$disk"
    partprobe "$disk"
    udevadm settle
    sleep 1
}

format_partitions() {
    local esp="$1" swap="$2" pool="$3"
    log_info "Formatting $esp as FAT32 (label $ESP_LABEL)..."
    mkfs.fat -F32 -n "$ESP_LABEL" "$esp"
    log_info "Formatting $swap as swap (label $SWAP_LABEL)..."
    mkswap -L "$SWAP_LABEL" "$swap"
    log_info "Formatting $pool as Btrfs (label $POOL_LABEL)..."
    mkfs.btrfs -f -L "$POOL_LABEL" "$pool"
}

create_subvolumes() {
    local pool="$1"
    local top
    top=$(mktemp -d)
    mount -t btrfs -o "compress=zstd:1,noatime,ssd,space_cache=v2" "$pool" "$top"
    local subvol
    for subvol in "${BTRFS_SUBVOLUMES[@]}"; do
        log_info "Creating subvolume $subvol..."
        btrfs subvolume create "$top/$subvol"
    done
    log_info "Snapshotting empty root-active into root-blank (impermanence baseline)..."
    btrfs subvolume delete "$top/root-blank"
    btrfs subvolume snapshot -r "$top/root-active" "$top/root-blank"
    umount "$top"
    rmdir "$top"
}

main() {
    require_root
    local disk="${1:?usage: format-drive.sh /dev/nvme0n1}"
    [[ -b "$disk" ]] || die "$disk is not a block device"

    local bytes
    bytes=$(blockdev --getsize64 "$disk")
    check_size "$bytes"
    refuse_if_mounted "$disk"
    warn_existing_partitions "$disk"

    confirm_typed "DESTROY $disk" "This ERASES ALL DATA on $disk ($(numfmt --to=iec "$bytes"))."

    partition_disk "$disk"

    local esp swap pool
    esp=$(partition_suffix "$disk" 1)
    swap=$(partition_suffix "$disk" 2)
    pool=$(partition_suffix "$disk" 3)

    format_partitions "$esp" "$swap" "$pool"
    create_subvolumes "$pool"

    log_info "Done. Layout on $disk:"
    log_info "  $esp  -> ESP (label $ESP_LABEL)"
    log_info "  $swap -> swap (label + partlabel $SWAP_LABEL)"
    log_info "  $pool -> Btrfs pool (label $POOL_LABEL): ${BTRFS_SUBVOLUMES[*]}"
    log_info "Labels match nix/modules/core/storage.nix. Next: sudo bash docs/install/mount-install.sh"
}

main "$@"
