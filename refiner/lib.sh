#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

REFINER_STATE_DIR="${REFINER_STATE_DIR:-/home/m/Projects/mandragora-usb-refiner/state}"
REFINER_TARGET_SIZE="${REFINER_TARGET_SIZE:-40G}"
REFINER_RAM="${REFINER_RAM:-6144}"
REFINER_VCPUS="${REFINER_VCPUS:-4}"

log()  { printf '[refiner] %s\n' "$*"; }
die()  { printf '[refiner] FATAL: %s\n' "$*" >&2; exit 1; }

ensure_state_dir() {
    mkdir -p "$REFINER_STATE_DIR"
}

check_kvm() {
    [[ -r /dev/kvm && -w /dev/kvm ]] \
        || die "/dev/kvm not accessible. Add your user to the 'kvm' group: sudo usermod -aG kvm \$USER && relogin."
}

check_ram() {
    local free_mb
    free_mb=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
    if (( free_mb < 12000 )); then
        log "WARNING: less than 12 GB RAM available (${free_mb} MB). VM may be tight."
    fi
}

allocate_run_log() {
    local ts
    ts=$(date +%Y%m%d-%H%M%S)
    REFINER_RUN_LOG="${REFINER_STATE_DIR}/run-${ts}-$$.log"
    log "Run log: $REFINER_RUN_LOG"
}

prepare_ovmf_vars() {
    local src_vars="${1:?prepare_ovmf_vars: pass OVMF_VARS source path}"
    local dst="${REFINER_STATE_DIR}/OVMF_VARS.fd"
    rm -f "$dst"
    cp "$src_vars" "$dst"
    chmod u+w "$dst"
    REFINER_OVMF_VARS="$dst"
}

prepare_target_disk() {
    local dst="${REFINER_STATE_DIR}/target.qcow2"
    rm -f "$dst"
    qemu-img create -f qcow2 "$dst" "$REFINER_TARGET_SIZE" >/dev/null
    REFINER_TARGET="$dst"
}
