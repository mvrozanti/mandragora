#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=./lib.sh
source "$(dirname "$(readlink -f "$0")")/lib.sh"

USB_IMG="${MANDRAGORA_USB_IMG:?MANDRAGORA_USB_IMG must point to a raw USB image}"
OVMF_CODE="${MANDRAGORA_OVMF_CODE:?MANDRAGORA_OVMF_CODE must point to OVMF_CODE.fd}"
OVMF_VARS_SRC="${MANDRAGORA_OVMF_VARS:?MANDRAGORA_OVMF_VARS must point to OVMF_VARS.fd template}"

SSH_PORT="${REFINER_SSH_PORT:-2222}"
SCENARIO=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ram) REFINER_RAM="$2"; shift 2 ;;
        --vcpus) REFINER_VCPUS="$2"; shift 2 ;;
        --ssh-port) SSH_PORT="$2"; shift 2 ;;
        --scenario) SCENARIO="$2"; shift 2 ;;
        --) shift; break ;;
        *) die "unknown arg: $1" ;;
    esac
done

check_kvm
check_ram
ensure_state_dir
allocate_run_log
prepare_ovmf_vars "$OVMF_VARS_SRC"

TARGET_SIZE="$REFINER_TARGET_SIZE"
EXTRA_TARGETS_COUNT=0
NETDEV_ARGS=( -netdev "user,id=net0,hostfwd=tcp::${SSH_PORT}-:22" -device "virtio-net,netdev=net0" )
RTC_ARGS=()

case "$SCENARIO" in
    "")           ;;
    multi-disk)   EXTRA_TARGETS_COUNT=2 ;;
    small-target) TARGET_SIZE=10G ;;
    no-network)   NETDEV_ARGS=() ;;
    clock-skew)   RTC_ARGS=( -rtc base="2010-01-01" ) ;;
    *)            die "unknown scenario: $SCENARIO" ;;
esac

prepare_target_disk "$TARGET_SIZE"
prepare_extra_targets "$EXTRA_TARGETS_COUNT"

log "Booting mandragora-usb image: $USB_IMG"
log "Target disk: $REFINER_TARGET ($TARGET_SIZE)"
[[ -n "$SCENARIO" ]] && log "Scenario: $SCENARIO"
(( EXTRA_TARGETS_COUNT > 0 )) && log "Extra target disks: $EXTRA_TARGETS_COUNT"
if (( ${#NETDEV_ARGS[@]} > 0 )); then
    log "SSH: ssh -p $SSH_PORT m@localhost  (password: mandragora)"
else
    log "SSH: disabled (no-network scenario)"
fi
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
    "${REFINER_EXTRA_DRIVES[@]}" \
    "${NETDEV_ARGS[@]}" \
    "${RTC_ARGS[@]}" \
    -device virtio-rng-pci \
    -display none \
    -serial mon:stdio \
    2>&1 | tee "$REFINER_RUN_LOG"
