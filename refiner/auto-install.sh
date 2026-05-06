#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=./lib.sh
source "$(dirname "$(readlink -f "$0")")/lib.sh"

SSH_PORT="${REFINER_SSH_PORT:-2222}"
INSTALL_TIMEOUT="${REFINER_INSTALL_TIMEOUT:-1800}"
HOSTNAME="${REFINER_AUTO_HOSTNAME:-testbox}"
USER_NAME="${REFINER_AUTO_USER:-m}"
TARGET_DEV="${REFINER_AUTO_TARGET:-/dev/vdb}"
KEYMAP="${REFINER_AUTO_KEYMAP:-us}"
PASSWORD="${REFINER_AUTO_PASSWORD:-mandragora}"

RUN_VM_SH="$(dirname "$(readlink -f "$0")")/run-vm.sh"

ensure_state_dir

ssh_opts=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o ConnectTimeout=5
    -o ServerAliveInterval=10
    -p "$SSH_PORT"
)

vm_ssh() {
    sshpass -p "$PASSWORD" ssh "${ssh_opts[@]}" "${USER_NAME}@localhost" "$@"
}

log "Stage 1: boot refiner and drive install via ssh"
"$RUN_VM_SH" --ssh-port "$SSH_PORT" >/dev/null &
VM_PID=$!
trap 'kill $VM_PID 2>/dev/null || true; wait $VM_PID 2>/dev/null || true' EXIT INT TERM

log "waiting for sshd on localhost:$SSH_PORT (up to 5 min)..."
deadline=$(( $(date +%s) + 300 ))
while ! nc -z localhost "$SSH_PORT" 2>/dev/null; do
    if [[ $(date +%s) -gt $deadline ]]; then die "ssh port did not come up in 5 min"; fi
    sleep 5
done
while ! vm_ssh 'echo ready' 2>/dev/null | grep -q ready; do
    if [[ $(date +%s) -gt $deadline ]]; then die "ssh login did not succeed in 5 min"; fi
    sleep 5
done
log "ssh up"

log "running mandragora-install --auto (timeout ${INSTALL_TIMEOUT}s)..."
install_cmd="echo $PASSWORD | sudo -S mandragora-install --auto --target $TARGET_DEV --hostname $HOSTNAME --user $USER_NAME --keymap $KEYMAP"
if ! timeout "$INSTALL_TIMEOUT" sshpass -p "$PASSWORD" ssh "${ssh_opts[@]}" "${USER_NAME}@localhost" "$install_cmd"; then
    log "FATAL: install failed; preserving target qcow2"
    cp "$REFINER_TARGET" "${REFINER_STATE_DIR}/failed-target-$$.qcow2"
    log "target preserved at: ${REFINER_STATE_DIR}/failed-target-$$.qcow2"
    exit 2
fi

log "powering off VM"
vm_ssh "echo $PASSWORD | sudo -S poweroff" >/dev/null 2>&1 || true
wait "$VM_PID" 2>/dev/null || true
trap - EXIT INT TERM

log "--auto: PASSED"
exit 0
