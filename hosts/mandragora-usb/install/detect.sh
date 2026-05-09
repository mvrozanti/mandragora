#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=./lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib.sh"

_resolve_boot_disk() {
    local root_dev
    root_dev=$(findmnt -no SOURCE / | sed 's/\[.*\]//')
    lsblk -no PKNAME "$root_dev" 2>/dev/null | head -n1 | awk '{print "/dev/" $1}'
}

_list_block_disks() {
    lsblk -dno NAME,TYPE | awk '$2 == "disk" {print "/dev/" $1}'
}

_filter_targets() {
    local boot
    boot=$(_resolve_boot_disk)
    grep -v "^${boot}$" || true
}

_require_live_environment() {
    local marker="${MANDRAGORA_LIVE_MARKER:-/etc/mandragora-live}"
    if [[ ! -f "$marker" ]]; then
        die "refusing to detect target disks: not running on the mandragora live USB (no $marker)"
    fi
}

main() {
    _require_live_environment
    local boot
    boot=$(_resolve_boot_disk)
    log_info "Boot disk: $boot"

    local candidates
    candidates=$(_list_block_disks | _filter_targets)
    if [[ -z "$candidates" ]]; then
        die "No target disk available. The only disk is the boot media ($boot)."
    fi

    log_info "Candidate target disks:"
    while IFS= read -r dev; do
        local size model
        size=$(lsblk -dno SIZE "$dev")
        model=$(lsblk -dno MODEL "$dev" || echo "?")
        printf '  %s  %s  %s\n' "$dev" "$size" "$model" >&2
    done <<< "$candidates"

    echo "$candidates"
}

if [[ "${1:-}" != "--source-only" ]]; then
    main "$@"
fi
