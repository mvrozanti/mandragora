#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=./lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib.sh"

MIN_BYTES=$(( 30 * 1024 * 1024 * 1024 ))
WARN_BYTES=$(( 60 * 1024 * 1024 * 1024 ))

_check_size() {
    local bytes="$1"
    if (( bytes < MIN_BYTES )); then
        die "disk too small: $(numfmt --to=iec "$bytes") (minimum 30 GiB)"
    fi
    if (( bytes < WARN_BYTES )); then
        log_warn "disk is small: $(numfmt --to=iec "$bytes") (recommended >= 60 GiB)"
    fi
    return 0
}

_check_existing_partitions() {
    local dev="$1"
    local parts
    parts=$(lsblk -no NAME,TYPE,SIZE "$dev" | awk '$2 == "part" {print}')
    if [[ -n "$parts" ]]; then
        log_warn "disk $dev has existing partitions:"
        echo "$parts" >&2
        echo
        confirm_typed "WIPE" "All data on $dev will be destroyed."
    fi
}

_partition() {
    local dev="$1"
    log_info "Partitioning $dev..."
    sgdisk --zap-all "$dev"
    sgdisk -n 1:0:+1G -t 1:ef00 -c 1:ESP "$dev"
    sgdisk -n 2:0:0   -t 2:8300 -c 2:root "$dev"
    partprobe "$dev"
    sleep 1
}

_format() {
    local dev="$1"
    local p1 p2
    if [[ "$dev" =~ nvme || "$dev" =~ mmcblk ]]; then
        p1="${dev}p1"; p2="${dev}p2"
    else
        p1="${dev}1"; p2="${dev}2"
    fi
    log_info "Formatting $p1 (FAT32)..."
    mkfs.fat -F32 -n ESP "$p1"
    log_info "Formatting $p2 (ext4)..."
    mkfs.ext4 -L mandragora "$p2"
}

_mount() {
    local dev="$1"
    local p1 p2
    if [[ "$dev" =~ nvme || "$dev" =~ mmcblk ]]; then
        p1="${dev}p1"; p2="${dev}p2"
    else
        p1="${dev}1"; p2="${dev}2"
    fi
    mkdir -p /mnt
    mount "$p2" /mnt
    mkdir -p /mnt/boot
    mount "$p1" /mnt/boot
}

main() {
    require_root
    local dev="${1:?usage: format.sh /dev/sdX}"
    [[ -b "$dev" ]] || die "$dev is not a block device"

    local bytes
    bytes=$(blockdev --getsize64 "$dev")
    _check_size "$bytes"
    _check_existing_partitions "$dev"
    _partition "$dev"
    _format "$dev"
    _mount "$dev"

    log_info "Mounted: /mnt (root) and /mnt/boot (ESP)"
}

if [[ "${1:-}" != "--source-only" ]]; then
    main "$@"
fi
