#!/usr/bin/env bash
set -euo pipefail

VM_NAME="windows-11"
SRC_DIR="/home/m/Projects/vms/windows-11"
DEST_DISK="/var/lib/libvirt/images/${VM_NAME}.qcow2"
URI="qemu:///system"

ensure_disk() {
  if [ ! -f "$DEST_DISK" ]; then
    if [ ! -f "$SRC_DIR/disk.qcow2" ]; then
      echo "no source disk at $SRC_DIR/disk.qcow2" >&2
      exit 1
    fi
    echo "copying $SRC_DIR/disk.qcow2 → $DEST_DISK"
    install -m 0660 -g qemu-libvirtd /dev/null "$DEST_DISK"
    qemu-img convert -O qcow2 "$SRC_DIR/disk.qcow2" "$DEST_DISK"
  fi
}

vm_exists() {
  virsh --connect "$URI" dominfo "$VM_NAME" >/dev/null 2>&1
}

cmd_import() {
  if vm_exists; then
    echo "VM '$VM_NAME' already defined; nothing to import"
    return 0
  fi
  ensure_disk
  virt-install --connect "$URI" \
    --name "$VM_NAME" \
    --memory 8192 \
    --vcpus 4 \
    --cpu host-passthrough \
    --os-variant win11 \
    --disk path="$DEST_DISK",format=qcow2,bus=virtio \
    --network network=default,model=virtio \
    --graphics spice \
    --video qxl \
    --sound ich9 \
    --controller usb,model=qemu-xhci \
    --tpm backend.type=emulator,backend.version=2.0,model=tpm-crb \
    --boot uefi \
    --features kvm_hidden=on,acpi=on,apic=on \
    --import \
    --noautoconsole
  echo "VM '$VM_NAME' defined and starting."
  echo "After installing Windows + SSH inside, snapshot: mandragora-winvm snap fresh-install"
}

cmd_start()    { virsh --connect "$URI" start "$VM_NAME"; }
cmd_shutdown() { virsh --connect "$URI" shutdown "$VM_NAME"; }
cmd_kill()     { virsh --connect "$URI" destroy "$VM_NAME"; }
cmd_console()  { virt-viewer --connect "$URI" "$VM_NAME"; }
cmd_status()   { virsh --connect "$URI" dominfo "$VM_NAME"; }

cmd_snap() {
  local name="${1:?usage: mandragora-winvm snap <name>}"
  virsh --connect "$URI" snapshot-create-as "$VM_NAME" "$name" --disk-only --atomic
}

cmd_revert() {
  local name="${1:?usage: mandragora-winvm revert <name>}"
  virsh --connect "$URI" snapshot-revert "$VM_NAME" "$name" --force
}

cmd_snapshots() { virsh --connect "$URI" snapshot-list "$VM_NAME"; }

cmd_ip() {
  local mac ip
  mac=$(virsh --connect "$URI" dumpxml "$VM_NAME" 2>/dev/null \
    | grep -oE "mac address='[^']+" | head -1 | cut -d"'" -f2)
  [ -n "$mac" ] || { echo "no MAC found; is the VM defined?" >&2; exit 1; }
  ip=$(virsh --connect "$URI" net-dhcp-leases default 2>/dev/null \
    | awk -v m="$mac" '$3 == m {sub(/\/.*/,"",$5); print $5; exit}')
  [ -n "$ip" ] || { echo "no DHCP lease for $mac; is the VM running?" >&2; exit 1; }
  echo "$ip"
}

cmd_ssh() {
  local ip
  ip=$(cmd_ip)
  ssh "Quickemu@$ip" "$@"
}

cmd_undefine() {
  vm_exists || { echo "VM '$VM_NAME' is not defined"; return 0; }
  virsh --connect "$URI" destroy "$VM_NAME" 2>/dev/null || true
  virsh --connect "$URI" snapshot-list --name "$VM_NAME" 2>/dev/null \
    | while read -r s; do
        [ -n "$s" ] && virsh --connect "$URI" snapshot-delete "$VM_NAME" "$s" || true
      done
  virsh --connect "$URI" undefine "$VM_NAME" --nvram --remove-all-storage
}

usage() {
  cat <<USAGE
mandragora-winvm — libvirt-managed Windows 11 testbed

  import           copy disk from quickemu dir, define VM, take 'fresh-install' snapshot
  start            boot the VM
  shutdown         graceful shutdown via ACPI
  kill             force-kill (destroy)
  console          open SPICE console
  status           dominfo
  snap   NAME      create snapshot
  revert NAME      revert to snapshot
  snapshots        list snapshots
  ip               print VM IP (via guest-agent or DHCP lease)
  ssh    [args...] ssh m@<vm-ip> [args]
  undefine         tear down VM, snapshots, disk
USAGE
}

cmd="${1:-console}"; shift || true
case "$cmd" in
  import|start|shutdown|kill|console|status|snapshots|ip|undefine) "cmd_$cmd" ;;
  snap|revert|ssh) "cmd_$cmd" "$@" ;;
  help|-h|--help) usage ;;
  *) echo "unknown command: $cmd" >&2; usage; exit 2 ;;
esac
