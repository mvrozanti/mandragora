#!/bin/bash
set -euo pipefail

# =============================================================================
# Mandragora GPU Stress Test
# Dual-OS (Arch + NixOS) — RTX 5070 Ti validation
# =============================================================================

log() { echo "[*] $1"; }
err() { echo "[!] $1" >&2; }

# ---- Detect environment ----
if command -v pacman &>/dev/null; then
    ENV="arch"
elif command -v nix-shell &>/dev/null; then
    ENV="nixos"
else
    err "Unknown environment. Expected Arch or NixOS."
    exit 1
fi

# ---- NixOS: wrap in nix-shell with GPU packages ----
if [[ "$ENV" == "nixos" ]]; then
    log "NixOS detected. Launching GPU environment via nix-shell..."
    log "(This may take a moment on first run)"
    NIXPKGS_ALLOW_UNFREE=1 nix-shell \
        -p linuxPackages.nvidia_x11 \
        -p pciutils \
        -p mesa-demos \
        -p vulkan-tools \
        --impure \
        --run "
            echo '════════════════════════════════════════'
            echo '  Mandragora GPU Environment (NixOS)'
            echo '════════════════════════════════════════'
            echo ''
            echo 'Available commands:'
            echo '  nvidia-smi          GPU overview'
            echo '  watch -n1 nvidia-smi  live monitoring'
            echo '  glxinfo | head      OpenGL info'
            echo '  glxgears            basic GL test'
            echo '  vulkaninfo          Vulkan capabilities'
            echo '  lspci | grep -i vga GPU detection'
            echo ''
            exec bash
        "
    exit 0
fi

# ---- Arch: full interactive menu ----
# Ensure nvidia module is loaded
if ! lsmod | grep -q '^nvidia '; then
    log "Loading nvidia kernel module..."
    modprobe nvidia 2>/dev/null || err "Failed to load nvidia module. GPU may not be supported by installed drivers."
fi

# Quick GPU overview
if command -v nvidia-smi &>/dev/null; then
    echo ""
    nvidia-smi --query-gpu=name,driver_version,memory.total,memory.used,temperature.gpu,power.draw \
        --format=csv,noheader 2>/dev/null || true
    echo ""
fi

# Menu
while true; do
    echo "════════════════════════════════════════"
    echo "  Mandragora GPU Stress Test (Arch)"
    echo "════════════════════════════════════════"
    echo ""
    echo "  [1] nvidia-smi (live monitor)"
    echo "  [2] glmark2 --off-screen (benchmark)"
    echo "  [3] glxgears (basic OpenGL)"
    echo "  [4] vulkaninfo"
    echo "  [5] nvtop (GPU monitor TUI)"
    echo "  [6] gpu-burn (heavy stress test)"
    echo "  [q] quit"
    echo ""
    read -rp "Select: " choice

    case "$choice" in
        1)
            if command -v nvidia-smi &>/dev/null; then
                watch -n1 nvidia-smi
            else
                err "nvidia-smi not found. Install nvidia-utils."
            fi
            ;;
        2)
            if command -v glmark2 &>/dev/null; then
                glmark2 --off-screen
            else
                err "glmark2 not found. Install: pacman -S glmark2"
            fi
            ;;
        3)
            if command -v glxgears &>/dev/null; then
                log "Running glxgears for 10 seconds..."
                timeout 10 glxgears -info 2>&1 | tail -3 || true
            else
                err "glxgears not found. Install: pacman -S mesa-utils"
            fi
            ;;
        4)
            if command -v vulkaninfo &>/dev/null; then
                vulkaninfo --summary
            else
                err "vulkaninfo not found. Install: pacman -S vulkan-tools"
            fi
            ;;
        5)
            if command -v nvtop &>/dev/null; then
                nvtop
            else
                err "nvtop not found. Install: pacman -S nvtop"
            fi
            ;;
        6)
            GPU_BURN_DIR="/tmp/gpu-burn"
            if [[ ! -x "$GPU_BURN_DIR/gpu_burn" ]]; then
                log "gpu-burn not found. Downloading and compiling..."
                if ! command -v nvcc &>/dev/null; then
                    err "nvcc (CUDA toolkit) required for gpu-burn. Install: pacman -S cuda"
                    continue
                fi
                rm -rf "$GPU_BURN_DIR"
                git clone https://github.com/wilicc/gpu-burn.git "$GPU_BURN_DIR"
                (cd "$GPU_BURN_DIR" && make) || { err "gpu-burn build failed."; continue; }
            fi
            log "Running gpu-burn for 60 seconds..."
            (cd "$GPU_BURN_DIR" && ./gpu_burn 60)
            ;;
        q|Q)
            break
            ;;
        *)
            err "Invalid choice."
            ;;
    esac
    echo ""
done
