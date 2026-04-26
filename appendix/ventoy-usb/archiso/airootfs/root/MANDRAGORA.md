# Mandragora Bootstrap USB (Arch)

## First: Connect to Network

    nmtui                       WiFi picker (TUI)
    ping -c1 archlinux.org      verify connection

## What's Where

    /mnt/ventoy/                USB drive (mount -L Ventoy /mnt/ventoy if not mounted)
    /mnt/ventoy/docs/mandragora/   NixOS flake
    /mnt/ventoy/toolbox/        Scripts: format-drive, hw-diag, gpu-stress
    ~/MANDRAGORA.md             This file

## Available Tools

    claude / gemini / qwen      AI assistants (npm i -g @anthropic-ai/claude-code @google/gemini-cli @qwen-code/qwen-code)
    nvim                        Editor
    tmux                        Terminal multiplexer
    diag                        Full hardware diagnostics → /tmp/mandragora-hw-diag.log
    gpucheck                    GPU stress test menu
    sensors                     CPU/chipset temperatures
    htop / btop                 Process monitor
    fastfetch                   System info
    nmtui                       WiFi manager
    lf                          File manager (TUI)

## Install NixOS — Step by Step

### 1. Identify target disk

    lsblk -f

### 2. Partition + format + mount

    /mnt/ventoy/toolbox/format-drive.sh /dev/nvme0n1

### 3. Review hardware config

    nvim /mnt/etc/nixos/mandragora/hosts/mandragora-desktop/hardware-configuration.nix

### 4. Install

    nixos-install --flake /mnt/etc/nixos/mandragora#mandragora-desktop --no-root-passwd

### 5. Set passwords

    nixos-enter --root /mnt -c 'passwd m'
    nixos-enter --root /mnt -c 'passwd'

### 6. Reboot

    umount -R /mnt && reboot

## Diagnostics

    diag                        full hw report
    gpucheck                    GPU stress test
    sensors                     temperatures
    smartctl -a /dev/nvme0n1    NVMe health
    openrgb --list-devices      RGB detection

## Troubleshooting

### Ventoy partition not mounted

    mount -L Ventoy /mnt/ventoy

### Need nixos-install on Arch

    curl -L https://nixos.org/nix/install | sh
    . ~/.nix-profile/etc/profile.d/nix.sh
    nix-env -iA nixos.nixos-install-tools
