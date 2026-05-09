#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=./lib.sh
source "$(dirname "$(readlink -f "$0")")/lib.sh"

SSH_PORT="${REFINER_SSH_PORT:-2222}"
STAGE2_SSH_PORT="${REFINER_STAGE2_SSH_PORT:-2223}"
INSTALL_TIMEOUT="${REFINER_INSTALL_TIMEOUT:-1800}"
STAGE2_TIMEOUT="${REFINER_STAGE2_TIMEOUT:-300}"
HOSTNAME="${REFINER_AUTO_HOSTNAME:-testbox}"
USER_NAME="${REFINER_AUTO_USER:-m}"
TARGET_DEV="${REFINER_AUTO_TARGET:-/dev/vdb}"
KEYMAP="${REFINER_AUTO_KEYMAP:-us}"
PASSWORD="${REFINER_AUTO_PASSWORD:-mandragora}"
SCENARIO=""
SKIP_STAGE2=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scenario)   SCENARIO="$2"; shift 2 ;;
        --ssh-port)   SSH_PORT="$2"; shift 2 ;;
        --no-stage2)  SKIP_STAGE2=1; shift ;;
        *) die "unknown arg: $1" ;;
    esac
done

RUN_VM_SH="$(dirname "$(readlink -f "$0")")/run-vm.sh"

ensure_state_dir
REFINER_TARGET="${REFINER_STATE_DIR}/target.qcow2"

ssh_opts=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o ConnectTimeout=5
    -o ServerAliveInterval=10
)

vm_ssh() {
    local port="$1"; shift
    sshpass -p "$PASSWORD" ssh "${ssh_opts[@]}" -p "$port" "${USER_NAME}@localhost" "$@"
}

run_vm_args=( --ssh-port "$SSH_PORT" )
[[ -n "$SCENARIO" ]] && run_vm_args+=( --scenario "$SCENARIO" )

log "Stage 1: boot refiner and drive install via ssh"
[[ -n "$SCENARIO" ]] && log "  scenario: $SCENARIO"
"$RUN_VM_SH" "${run_vm_args[@]}" >/dev/null &
VM_PID=$!
trap 'kill $VM_PID 2>/dev/null || true; wait $VM_PID 2>/dev/null || true' EXIT INT TERM

log "waiting for sshd on localhost:$SSH_PORT (up to 5 min)..."
deadline=$(( $(date +%s) + 300 ))
while ! nc -z localhost "$SSH_PORT" 2>/dev/null; do
    if [[ $(date +%s) -gt $deadline ]]; then die "ssh port did not come up in 5 min"; fi
    sleep 5
done
while ! vm_ssh "$SSH_PORT" 'echo ready' 2>/dev/null | grep -q ready; do
    if [[ $(date +%s) -gt $deadline ]]; then die "ssh login did not succeed in 5 min"; fi
    sleep 5
done
log "ssh up"

log "running mandragora-install --auto (timeout ${INSTALL_TIMEOUT}s)..."
install_cmd="echo $PASSWORD | sudo -S mandragora-install --auto --target $TARGET_DEV --hostname $HOSTNAME --user $USER_NAME --keymap $KEYMAP"
if ! timeout "$INSTALL_TIMEOUT" sshpass -p "$PASSWORD" ssh "${ssh_opts[@]}" -p "$SSH_PORT" "${USER_NAME}@localhost" "$install_cmd"; then
    log "FATAL: install failed; preserving target qcow2"
    cp "$REFINER_TARGET" "${REFINER_STATE_DIR}/failed-target-$$.qcow2"
    log "target preserved at: ${REFINER_STATE_DIR}/failed-target-$$.qcow2"
    exit 2
fi

log "powering off stage 1 VM"
vm_ssh "$SSH_PORT" "echo $PASSWORD | sudo -S poweroff" >/dev/null 2>&1 || true
wait "$VM_PID" 2>/dev/null || true
trap - EXIT INT TERM

if (( SKIP_STAGE2 )); then
    log "--auto (stage 1 only): PASSED"
    exit 0
fi

OVMF_CODE="${MANDRAGORA_OVMF_CODE:?MANDRAGORA_OVMF_CODE must point to OVMF_CODE.fd}"
OVMF_VARS_RUNTIME="${REFINER_STATE_DIR}/OVMF_VARS.fd"
[[ -f "$OVMF_VARS_RUNTIME" ]] || die "stage 2: OVMF_VARS.fd from stage 1 missing"

log "Stage 2: boot installed target qcow2 standalone (sshd on :$STAGE2_SSH_PORT)"
STAGE2_LOG="${REFINER_STATE_DIR}/stage2-$$.log"
qemu-system-x86_64 \
    -enable-kvm \
    -m "$REFINER_RAM" \
    -smp "$REFINER_VCPUS" \
    -drive "if=pflash,format=raw,readonly=on,file=${OVMF_CODE}" \
    -drive "if=pflash,format=raw,file=${OVMF_VARS_RUNTIME}" \
    -drive "file=${REFINER_TARGET},if=virtio,format=qcow2" \
    -netdev "user,id=net0,hostfwd=tcp::${STAGE2_SSH_PORT}-:22" \
    -device "virtio-net,netdev=net0" \
    -device virtio-rng-pci \
    -display none \
    -serial "file:${STAGE2_LOG}" \
    -monitor none \
    >/dev/null 2>&1 &
STAGE2_PID=$!
trap 'kill $STAGE2_PID 2>/dev/null || true; wait $STAGE2_PID 2>/dev/null || true' EXIT INT TERM

log "waiting for sshd on installed target localhost:$STAGE2_SSH_PORT (up to ${STAGE2_TIMEOUT}s)..."
deadline=$(( $(date +%s) + STAGE2_TIMEOUT ))
while ! nc -z localhost "$STAGE2_SSH_PORT" 2>/dev/null; do
    if ! kill -0 "$STAGE2_PID" 2>/dev/null; then
        log "FATAL: stage 2 VM exited; preserving qcow2 + serial log"
        cp "$REFINER_TARGET" "${REFINER_STATE_DIR}/stage2-failed-target-$$.qcow2"
        log "target preserved at: ${REFINER_STATE_DIR}/stage2-failed-target-$$.qcow2"
        log "serial log:           $STAGE2_LOG"
        exit 3
    fi
    if [[ $(date +%s) -gt $deadline ]]; then
        log "FATAL: stage 2 sshd timeout; preserving qcow2 + serial log"
        cp "$REFINER_TARGET" "${REFINER_STATE_DIR}/stage2-timeout-target-$$.qcow2"
        log "target preserved at: ${REFINER_STATE_DIR}/stage2-timeout-target-$$.qcow2"
        log "serial log:           $STAGE2_LOG"
        exit 4
    fi
    sleep 5
done

if ! vm_ssh "$STAGE2_SSH_PORT" 'echo booted' 2>/dev/null | grep -q booted; then
    die "stage 2: ssh port up but login failed"
fi
log "stage 2: ssh login on installed target verified"

log "powering off stage 2 VM"
vm_ssh "$STAGE2_SSH_PORT" "echo $PASSWORD | sudo -S poweroff" >/dev/null 2>&1 || true
wait "$STAGE2_PID" 2>/dev/null || true
trap - EXIT INT TERM

log "--auto: PASSED (install + first-boot)"
exit 0
