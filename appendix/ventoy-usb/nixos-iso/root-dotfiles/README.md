# Mandragora Bootstrap USB

You booted from the Mandragora USB. Everything you need is here.

## First: Connect to Network

    nmtui                       # WiFi picker (TUI)
    ping -c1 nixos.org          # verify connection

## What's Where

    /mnt/ventoy/                USB drive (auto-mounted, read/write)
    /mnt/ventoy/docs/mandragora-nixos/   NixOS flake (your system config)
    /mnt/ventoy/toolbox/        Scripts: format-drive, hw-diag, gpu-stress
    ~/README.md                 This file

## Available Tools

    claude / gemini / qwen      AI coding assistants (auto-installed on first boot)
    nvim                        Editor
    tmux                        Terminal multiplexer (already running)
    diag                        Full hardware diagnostics → /tmp/mandragora-hw-diag.log
    gpucheck                    GPU stress test menu
    sensors                     CPU/chipset temperatures
    htop / btop                 Process monitor
    fastfetch                   System info
    nmtui                       WiFi manager
    lf                          File manager (TUI)

## Install NixOS — Step by Step

### 1. Identify your target disk

    lsblk -f

  Look for your NVMe (usually /dev/nvme0n1) or SATA drive (/dev/sda).
  DO NOT pick the USB — it shows as Ventoy/VTOYEFI.

### 2. Partition + format + mount (one command)

    /mnt/ventoy/toolbox/format-drive.sh /dev/nvme0n1

  This does everything:
  - Creates GPT partitions (4GB ESP, ~main Btrfs, 32GB swap)
  - Formats with correct filesystems and labels
  - Creates Btrfs subvolumes (root-blank, root-active, nix, persistent)
  - Mounts everything at /mnt
  - Copies the flake from USB to /mnt/etc/nixos/mandragora-nixos
  - Generates hardware-configuration.nix

### 3. Review hardware config

    nvim /mnt/etc/nixos/mandragora-nixos/hosts/mandragora-desktop/hardware-configuration.nix

  Verify disk UUIDs and kernel modules look sane.

### 4. Install NixOS

    nixos-install --flake /mnt/etc/nixos/mandragora-nixos#mandragora-desktop --no-root-passwd

  This downloads and builds the entire system. Takes a while.

### 5. Set passwords

    nixos-enter --root /mnt -c 'passwd m'
    nixos-enter --root /mnt -c 'passwd'        # root password (optional)

### 6. Reboot

    umount -R /mnt && reboot

  Remove the USB when prompted.

## Secrets (sops-nix + age)

sops and age are pre-installed. No extra flags needed.

    age-keygen -o /mnt/persistent/secrets/keys.txt
    age-keygen -y /mnt/persistent/secrets/keys.txt    # shows public key

    cd /mnt/etc/nixos/mandragora-nixos
    sops --age "$(age-keygen -y /mnt/persistent/secrets/keys.txt)" secrets/secrets.yaml

## Nix Commands

Flakes and nix-command are enabled globally. These just work:

    nix shell nixpkgs#sops nixpkgs#age
    nix build .#nixosConfigurations.mandragora-desktop.config.system.build.toplevel
    nix flake show
    nix search nixpkgs firefox

## Diagnostics

    diag                        # full hw report (CPU, GPU, RAM, disk, thermals, RGB)
    gpucheck                    # GPU stress test menu
    sensors                     # quick thermal check
    smartctl -a /dev/nvme0n1    # NVMe health
    nvme smart-log /dev/nvme0n1 # NVMe SMART data
    openrgb --list-devices      # RGB hardware detection

## Troubleshooting

### "command not found: claude" (or gemini/qwen)
AI tools auto-install on first boot with internet. Manual install:

    npm install -g @anthropic-ai/claude-code @google/gemini-cli @qwen-code/qwen-code

### Ventoy partition not mounted

    mount -L Ventoy /mnt/ventoy

### Can't write to Ventoy partition

    mount -o remount,rw /mnt/ventoy

### nixos-install fails with "flake not found"
Make sure format-drive.sh copied the flake, or clone manually:

    git clone <your-repo-url> /mnt/etc/nixos/mandragora-nixos

### Need a package temporarily

    nix shell nixpkgs#<package>
