#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=./lib.sh
source "$(dirname "$(readlink -f "$0")")/lib.sh"

USB_IMG="${MANDRAGORA_USB_IMG:?MANDRAGORA_USB_IMG must point to a raw USB image}"
OVMF_CODE="${MANDRAGORA_OVMF_CODE:?MANDRAGORA_OVMF_CODE must point to OVMF_CODE.fd}"
OVMF_VARS_SRC="${MANDRAGORA_OVMF_VARS:?MANDRAGORA_OVMF_VARS must point to OVMF_VARS.fd template}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ram) REFINER_RAM="$2"; shift 2 ;;
        --vcpus) REFINER_VCPUS="$2"; shift 2 ;;
        --) shift; break ;;
        *) die "unknown arg: $1" ;;
    esac
done

check_kvm
check_ram
ensure_state_dir
allocate_run_log
prepare_ovmf_vars "$OVMF_VARS_SRC"
prepare_target_disk

log "Booting mandragora-usb image: $USB_IMG"
log "Target disk: $REFINER_TARGET ($REFINER_TARGET_SIZE)"
log "Press Ctrl+A then X to terminate QEMU."
log "---"

exec qemu-system-x86_64 \
    -enable-kvm \
    -m "$REFINER_RAM" \
    -smp "$REFINER_VCPUS" \
    -drive "if=pflash,format=raw,readonly=on,file=${OVMF_CODE}" \
    -drive "if=pflash,format=raw,file=${REFINER_OVMF_VARS}" \
    -drive "file=${USB_IMG},if=virtio,format=raw,snapshot=on" \
    -drive "file=${REFINER_TARGET},if=virtio,format=qcow2" \
    -netdev user,id=net0 \
    -device virtio-net,netdev=net0 \
    -device virtio-rng-pci \
    -display none \
    -serial mon:stdio \
    2>&1 | tee "$REFINER_RUN_LOG"
