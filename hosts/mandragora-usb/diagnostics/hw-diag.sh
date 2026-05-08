#!/bin/bash
set -euo pipefail

# =============================================================================
# Mandragora Hardware Diagnostics
# Dual-OS (Arch + NixOS) — outputs to terminal + log file
# =============================================================================

LOG="/tmp/mandragora-hw-diag.log"
: > "$LOG"

divider() {
    local msg="$1"
    local line
    line="$(printf '═%.0s' {1..60})"
    echo ""
    echo "$line"
    echo "  $msg"
    echo "$line"
}

run_section() {
    local title="$1"
    shift
    divider "$title" | tee -a "$LOG"
    for cmd in "$@"; do
        if command -v "$(echo "$cmd" | awk '{print $1}')" &>/dev/null; then
            eval "$cmd" 2>&1 | tee -a "$LOG" || true
        else
            echo "  [skip] $(echo "$cmd" | awk '{print $1}') not found" | tee -a "$LOG"
        fi
    done
}

echo "Mandragora Hardware Diagnostics — $(date)" | tee -a "$LOG"
echo "OS: $(uname -srm)" | tee -a "$LOG"

# ---- CPU ----
run_section "CPU" \
    "lscpu | grep -E 'Model name|CPU\(s\)|Thread|Core|MHz|Cache|Architecture'"

# ---- Memory ----
run_section "Memory" \
    "free -h" \
    "dmidecode -t memory 2>/dev/null | grep -E 'Size|Type|Speed|Manufacturer|Part Number|Configured'"

# ---- GPU ----
run_section "GPU" \
    "lspci | grep -iE 'vga|3d|display'" \
    "nvidia-smi --query-gpu=name,driver_version,memory.total,temperature.gpu,power.draw --format=csv,noheader"

# ---- Storage ----
run_section "Storage" \
    "lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL" \
    "smartctl -a /dev/nvme0n1 2>/dev/null | grep -E 'Model|Capacity|Health|Temperature|Power On'" \
    "nvme smart-log /dev/nvme0n1 2>/dev/null"

# ---- Thermals ----
run_section "Thermals" \
    "sensors"

# ---- Network ----
run_section "Network" \
    "ip -br link" \
    "ip -br addr" \
    "iwconfig 2>/dev/null | grep -E 'ESSID|Signal|Bit Rate'"

# ---- USB ----
run_section "USB Devices" \
    "lsusb"

# ---- Motherboard ----
run_section "Motherboard" \
    "dmidecode -t baseboard 2>/dev/null | grep -E 'Manufacturer|Product|Version|Serial'"

# ---- RGB ----
run_section "RGB Devices" \
    "openrgb --list-devices --noautoconnect"

# ---- Summary ----
divider "Done" | tee -a "$LOG"
echo "Full log saved to: $LOG" | tee -a "$LOG"
