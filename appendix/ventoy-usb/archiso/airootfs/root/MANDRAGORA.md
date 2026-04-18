# Mandragora Bootstrap USB

## WiFi
    nmtui                  open WiFi picker (TUI)

## AI
    claude                 Claude Code (login on first run)
    gemini                 Gemini CLI (login on first run)

## Diagnostics
    diag                   full hardware report → /tmp/mandragora-hw-diag.log
    gpucheck               GPU stress test menu
    sensors                CPU / chipset temps
    nvtop                  GPU live monitor (TUI)
    htop / btop            process monitor

## RGB
    openrgb --list-devices check RGB hardware detection
    openrgb --gui          GUI (needs display)

## Storage
    lsblk -f               disk overview
    smartctl -a /dev/nvme0n1   NVMe health
    nvme smart-log /dev/nvme0n1

## USB (this drive)
    ventoy                 cd /mnt/ventoy
    ls ~/toolbox           shared scripts

## NixOS install (when ready)
    nixos-install          after mounting target partition
    nixos-generate-config --root /mnt
