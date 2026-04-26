#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=./lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib.sh"

_detect_microcode_from_vendor() {
    case "$1" in
        GenuineIntel) echo "intel-ucode" ;;
        AuthenticAMD) echo "amd-ucode" ;;
        *) echo "none" ;;
    esac
}

_detect_microcode() {
    local vendor
    vendor=$(awk -F: '/^vendor_id/ {gsub(/ /, "", $2); print $2; exit}' /proc/cpuinfo)
    _detect_microcode_from_vendor "$vendor"
}

_detect_gpu_from_id() {
    case "${1%%:*}" in
        8086) echo "intel" ;;
        1002) echo "amd" ;;
        10de) echo "nouveau" ;;
        *)    echo "none" ;;
    esac
}

_detect_gpu() {
    local first_vga
    first_vga=$(lspci -nn | grep -i 'VGA\|3D' | head -n1 | grep -oE '\[[0-9a-f]+:[0-9a-f]+\]' | tr -d '[]')
    [[ -n "$first_vga" ]] && _detect_gpu_from_id "$first_vga" || echo "none"
}

_render_template() {
    local in_file="$1"
    local out_file="$2"
    shift 2
    local content
    content=$(cat "$in_file")
    while [[ $# -gt 0 ]]; do
        local kv="$1"
        local k="${kv%%=*}"
        local v="${kv#*=}"
        content="${content//@${k}@/${v}}"
        shift
    done
    printf '%s' "$content" > "$out_file"
}

_microcode_import() {
    case "$1" in
        intel-ucode) echo '({ ... }: { hardware.cpu.intel.updateMicrocode = true; })' ;;
        amd-ucode)   echo '({ ... }: { hardware.cpu.amd.updateMicrocode = true; })' ;;
        none)        echo '({ ... }: {})' ;;
    esac
}

_gpu_block() {
    case "$1" in
        intel) echo 'hardware.opengl.enable = true; hardware.opengl.extraPackages = with pkgs; [ intel-media-driver ];' ;;
        amd)   echo 'hardware.opengl.enable = true;' ;;
        nouveau) echo 'services.xserver.videoDrivers = [ "nouveau" ]; hardware.opengl.enable = true;' ;;
        none)  echo '' ;;
    esac
}

main() {
    require_root
    local hostname=mandragora-test user=m keymap=us gpu=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --hostname) hostname="$2"; shift 2 ;;
            --user)     user="$2"; shift 2 ;;
            --keymap)   keymap="$2"; shift 2 ;;
            --gpu)      gpu="$2"; shift 2 ;;
            *) die "unknown arg: $1" ;;
        esac
    done

    [[ -z "$gpu" ]] && gpu=$(_detect_gpu)
    local microcode
    microcode=$(_detect_microcode)

    log_info "Hostname:  $hostname"
    log_info "User:      $user"
    log_info "Keymap:    $keymap"
    log_info "Microcode: $microcode"
    log_info "GPU:       $gpu"

    nixos-generate-config --root /mnt --no-filesystems
    log_info "hardware-configuration.nix generated at /mnt/etc/nixos/hardware-configuration.nix"

    local target_dir=/mnt/etc/nixos/mandragora/hosts/$hostname
    mkdir -p "$target_dir"
    cp /mnt/etc/nixos/hardware-configuration.nix "$target_dir/"

    local tmpl_dir
    tmpl_dir=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
    _render_template "$tmpl_dir/host-template.nix" "$target_dir/default.nix" \
        "HOSTNAME=$hostname" \
        "USER=$user" \
        "KEYMAP=$keymap" \
        "MICROCODE_IMPORT=$(_microcode_import "$microcode")" \
        "GPU_DRIVER_BLOCK=$(_gpu_block "$gpu")"

    log_info "Rendered: $target_dir/default.nix"
}

if [[ "${1:-}" != "--source-only" ]]; then
    main "$@"
fi
