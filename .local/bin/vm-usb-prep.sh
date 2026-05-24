set -euo pipefail

[[ $# -eq 1 ]] || { echo "usage: vm-usb-prep vid:pid" >&2; exit 2; }
spec="$1"

[[ "$spec" =~ ^[0-9a-fA-F]{4}:[0-9a-fA-F]{4}$ ]] || {
    echo "invalid vid:pid: $spec" >&2
    exit 2
}

vid="${spec%%:*}"
pid="${spec##*:}"
target_user="${SUDO_USER:-${USER:-root}}"

found=0
for vfile in /sys/bus/usb/devices/*/idVendor; do
    [[ "$(cat "$vfile" 2>/dev/null)" == "$vid" ]] || continue
    base="${vfile%/idVendor}"
    [[ "$(cat "$base/idProduct" 2>/dev/null)" == "$pid" ]] || continue
    bus=$(cat "$base/busnum" 2>/dev/null)
    dev=$(cat "$base/devnum" 2>/dev/null)
    [[ -n "$bus" && -n "$dev" ]] || continue
    node="/dev/bus/usb/$(printf %03d "$bus")/$(printf %03d "$dev")"
    if [[ -e "$node" ]]; then
        setfacl -m "u:${target_user}:rw" "$node" || true
    fi
    for iface in "$base"/"$(basename "$base")":*; do
        [[ -d "$iface" ]] || continue
        drv="$(readlink "$iface/driver" 2>/dev/null | sed 's|.*/||')"
        [[ -z "$drv" ]] && continue
        ifname="$(basename "$iface")"
        echo "$ifname" > "/sys/bus/usb/drivers/$drv/unbind" 2>/dev/null || true
    done
    found=1
    break
done

[[ "$found" -eq 1 ]] || { echo "device $spec not present" >&2; exit 3; }
