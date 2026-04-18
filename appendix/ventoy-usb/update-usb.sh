#!/bin/bash
set -euo pipefail

# =============================================================================
# Update Mandragora USB with latest ISO, toolbox, repo, and credentials
# =============================================================================
# Usage: sudo ./update-usb.sh /dev/sdX
# =============================================================================

USB_DEV="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ISO_CACHE="${ISO_CACHE:-$HOME/iso_cache}"
USB_MNT="/tmp/mandragora-usb"
PERSIST_MNT="/tmp/mandragora-persist"

log()  { echo "[*] $1"; }
warn() { echo "[!] $1"; }
err()  { echo "[!!] $1" >&2; exit 1; }

cleanup() {
    umount "$PERSIST_MNT" 2>/dev/null || true
    [[ -n "${LOOP_DEV:-}" ]] && losetup -d "$LOOP_DEV" 2>/dev/null || true
    umount "$USB_MNT" 2>/dev/null || true
    rmdir "$PERSIST_MNT" "$USB_MNT" 2>/dev/null || true
}
trap cleanup EXIT

[[ $EUID -ne 0 ]] && err "Must run as root."

if [[ -z "$USB_DEV" ]]; then
    echo "Usage: $0 /dev/sdX"
    echo ""
    echo "Removable devices:"
    lsblk -d -o NAME,SIZE,MODEL,TRAN,RM | awk 'NR==1 || $5=="1"'
    exit 1
fi

[[ ! -b "$USB_DEV" ]] && err "$USB_DEV is not a block device."

# ---- Find the exFAT data partition ----
DATA_PART=""
for part in "${USB_DEV}1" "${USB_DEV}2" "${USB_DEV}3"; do
    if [[ -b "$part" ]] && [[ "$(lsblk -no FSTYPE "$part" 2>/dev/null)" == "exfat" ]]; then
        DATA_PART="$part"
        break
    fi
done
[[ -z "$DATA_PART" ]] && err "No exFAT partition found on $USB_DEV. Is this a Ventoy USB?"

# ---- Mount USB ----
mkdir -p "$USB_MNT"
log "Mounting $DATA_PART at $USB_MNT..."
mount "$DATA_PART" "$USB_MNT"

# ---- Copy ISO ----
ISO="$ISO_CACHE/mandragora-nixos.iso"
if [[ -f "$ISO" ]]; then
    log "Copying ISO ($(du -sh "$ISO" | cut -f1))... this takes a minute."
    cp "$ISO" "$USB_MNT/isos/mandragora-nixos.iso"
else
    warn "No ISO found at $ISO. Skipping."
fi

# ---- Copy toolbox ----
log "Updating toolbox scripts..."
cp "$SCRIPT_DIR/toolbox/"*.sh "$USB_MNT/toolbox/" 2>/dev/null || true
chmod +x "$USB_MNT/toolbox/"*.sh 2>/dev/null || true

# ---- Copy ventoy config ----
log "Updating ventoy.json..."
cp "$SCRIPT_DIR/ventoy.json" "$USB_MNT/ventoy/ventoy.json"

# ---- Copy repo ----
log "Updating repo in docs/..."
rm -rf "$USB_MNT/docs/mandragora-nixos"
cp -r "$REPO_DIR" "$USB_MNT/docs/mandragora-nixos"

# ---- Copy credentials into persist image ----
PERSIST_IMG="$USB_MNT/persistence/nixos_persistence.dat"
CREDS="$HOME/.claude/.credentials.json"
# check calling user's home too (since we're running as sudo)
SUDO_CREDS="${SUDO_USER:+/home/$SUDO_USER/.claude/.credentials.json}"

if [[ ! -f "$PERSIST_IMG" ]]; then
    warn "Persistence image not found at $PERSIST_IMG. Skipping credentials."
else
    log "Mounting persistence image..."
    mkdir -p "$PERSIST_MNT"
    LOOP_DEV=$(losetup --find --show "$PERSIST_IMG") || { warn "losetup failed. Skipping persist."; LOOP_DEV=""; }
    if [[ -n "$LOOP_DEV" ]]; then
    mount "$LOOP_DEV" "$PERSIST_MNT"

    mkdir -p "$PERSIST_MNT"/{claude,ssh,npm-global/bin,zsh-history}
    chmod 755 "$PERSIST_MNT" "$PERSIST_MNT"/npm-global "$PERSIST_MNT"/npm-global/bin "$PERSIST_MNT"/zsh-history
    chmod 700 "$PERSIST_MNT"/claude "$PERSIST_MNT"/ssh

    if [[ -n "$SUDO_CREDS" ]] && [[ -f "$SUDO_CREDS" ]]; then
        log "Copying Claude credentials from $SUDO_CREDS..."
        cp "$SUDO_CREDS" "$PERSIST_MNT/claude/.credentials.json"
        chmod 644 "$PERSIST_MNT/claude/.credentials.json"
    elif [[ -f "$CREDS" ]]; then
        log "Copying Claude credentials from $CREDS..."
        cp "$CREDS" "$PERSIST_MNT/claude/.credentials.json"
        chmod 644 "$PERSIST_MNT/claude/.credentials.json"
    else
        warn "No Claude credentials found. Run 'claude' to authenticate on the USB."
    fi

    # ---- Copy SSH keys ----
    SUDO_SSH="${SUDO_USER:+/home/$SUDO_USER/.ssh}"
    SSH_SRC="${SUDO_SSH:-$HOME/.ssh}"
    if [[ -d "$SSH_SRC" ]]; then
        log "Copying SSH keys from $SSH_SRC..."
        cp "$SSH_SRC"/id_* "$PERSIST_MNT/ssh/" 2>/dev/null || true
        cp "$SSH_SRC"/known_hosts "$PERSIST_MNT/ssh/" 2>/dev/null || true
        cp "$SSH_SRC"/config "$PERSIST_MNT/ssh/" 2>/dev/null || true
        chmod 600 "$PERSIST_MNT"/ssh/id_* 2>/dev/null || true
        chmod 644 "$PERSIST_MNT"/ssh/known_hosts "$PERSIST_MNT"/ssh/config 2>/dev/null || true
    else
        warn "No SSH keys found at $SSH_SRC."
    fi

    umount "$PERSIST_MNT"
    losetup -d "$LOOP_DEV" 2>/dev/null || true
    rmdir "$PERSIST_MNT" 2>/dev/null || true
    log "Persistence image updated."
    fi
fi

# ---- Done ----
sync
echo ""
echo "════════════════════════════════════════"
echo "  USB updated."
echo "════════════════════════════════════════"
[[ -f "$ISO" ]] && echo "  ISO:         $(du -sh "$USB_MNT/isos/mandragora-nixos.iso" | cut -f1)"
echo "  Toolbox:     updated"
echo "  Repo:        updated"
echo "  Credentials: $([ -f "$PERSIST_IMG" ] && echo "copied" || echo "skipped")"
df -h "$USB_MNT" | awk 'NR==2{print "  Free:        " $4}'
echo ""

umount "$USB_MNT"
rmdir "$USB_MNT" 2>/dev/null || true
