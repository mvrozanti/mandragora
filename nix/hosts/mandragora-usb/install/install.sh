#!/usr/bin/env bash

set -euo pipefail

DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
# shellcheck source=./lib.sh
source "$DIR/lib.sh"

AUTO=0
UPDATE=0
HOSTNAME=""
USER_NAME=""
TARGET=""
GPU=""
KEYMAP="us"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto)     AUTO=1; shift ;;
        --update)   UPDATE=1; shift ;;
        --hostname) HOSTNAME="$2"; shift 2 ;;
        --user)     USER_NAME="$2"; shift 2 ;;
        --target)   TARGET="$2"; shift 2 ;;
        --gpu)      GPU="$2"; shift 2 ;;
        --keymap)   KEYMAP="$2"; shift 2 ;;
        *) die "unknown arg: $1" ;;
    esac
done

require_root

[[ -n "$HOSTNAME"  ]] && validate_token hostname "$HOSTNAME"
[[ -n "$USER_NAME" ]] && validate_token user     "$USER_NAME"
[[ -n "$KEYMAP"    ]] && validate_token keymap   "$KEYMAP"

if (( UPDATE )); then
    if ping -c1 -W3 github.com >/dev/null 2>&1; then
        log_info "--update: refreshing flake from upstream..."
        git -C /etc/nixos/mandragora pull --ff-only origin master 2>/dev/null \
            || git -C /etc/nixos/mandragora pull --ff-only origin main 2>/dev/null \
            || log_warn "git pull failed; falling back to baked flake."
    else
        log_warn "--update requested but no network; falling back to baked flake."
    fi
else
    log_info "Using baked flake (pass --update to refresh from upstream)."
fi

USB_KEY_SRC="/etc/nixos/mandragora/secrets/usb-key.age"
USB_KEY_DST="/mnt/persistent/sops/usb-key.txt"
DECRYPTED=""
if [[ -f "$USB_KEY_SRC" ]]; then
    log_info "Sops USB key found. Will prompt for passphrase to decrypt."
    for attempt in 1 2 3; do
        if DECRYPTED=$(age -d "$USB_KEY_SRC" 2>/dev/null); then
            break
        fi
        log_warn "decryption failed (attempt $attempt of 3)"
        DECRYPTED=""
    done
    if [[ -z "$DECRYPTED" ]]; then
        log_warn "sops key not decrypted; install will continue without USB-host secrets"
    fi
fi

log_info "Detecting target disks..."
CANDIDATES=$(bash "$DIR/detect.sh" 2>/dev/null) || die "no candidate target disks"

if [[ -z "$TARGET" ]]; then
    if (( AUTO )); then die "--auto requires --target"; fi
    log_info "Available targets:"
    select dev in $CANDIDATES "abort"; do
        case "$dev" in
            "" ) log_warn "invalid choice"; continue ;;
            abort) die "aborted by user" ;;
            *) TARGET="$dev"; break ;;
        esac
    done
else
    if ! grep -qx "$TARGET" <<< "$CANDIDATES"; then
        die "target $TARGET is not in the candidate list (boot media filtered out)"
    fi
fi
log_info "Target: $TARGET"

if [[ -z "$HOSTNAME" ]]; then
    HOSTNAME="mandragora-$(tr -dc 'a-z0-9' </dev/urandom | head -c6)"
    if (( ! AUTO )); then
        read -rp "Hostname [$HOSTNAME]: " input; HOSTNAME="${input:-$HOSTNAME}"
    fi
fi
if [[ -z "$USER_NAME" ]]; then
    USER_NAME="m"
    if (( ! AUTO )); then
        read -rp "User [$USER_NAME]: " input; USER_NAME="${input:-$USER_NAME}"
    fi
fi
if (( ! AUTO )); then
    read -rp "Keymap [$KEYMAP]: " input; KEYMAP="${input:-$KEYMAP}"
fi

validate_token hostname "$HOSTNAME"
validate_token user     "$USER_NAME"
validate_token keymap   "$KEYMAP"

log_info "Formatting $TARGET..."
bash "$DIR/format.sh" "$TARGET"

log_info "Copying flake..."
mkdir -p /mnt/etc/nixos/mandragora
cp -aL /etc/nixos/mandragora/. /mnt/etc/nixos/mandragora/
chmod -R u+w /mnt/etc/nixos/mandragora

log_info "Rendering host config..."
render_args=( --hostname "$HOSTNAME" --user "$USER_NAME" --keymap "$KEYMAP" )
[[ -n "$GPU" ]] && render_args+=( --gpu "$GPU" )
bash "$DIR/render-config.sh" "${render_args[@]}"

log_info "Running nixos-install..."
nixos-install --no-root-passwd --flake "/mnt/etc/nixos/mandragora#$HOSTNAME"

if [[ -n "$DECRYPTED" ]]; then
    mkdir -p "$(dirname "$USB_KEY_DST")"
    printf '%s' "$DECRYPTED" > "$USB_KEY_DST"
    chmod 600 "$USB_KEY_DST"
    log_info "Decrypted age key placed at $USB_KEY_DST"
fi
unset DECRYPTED

log_info "Install complete. Reboot, remove the USB, and select the target disk."
