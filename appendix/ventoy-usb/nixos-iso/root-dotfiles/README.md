# Mandragora Bootstrap USB

You booted from the Mandragora USB. Everything you need is here.

## First: Connect to Network

    nmtui                       # WiFi picker (TUI)
    ping -c1 nixos.org          # verify connection

## What's Where

    /mnt/ventoy/                USB drive (auto-mounted, read/write)
    /mnt/ventoy/docs/mandragora/   NixOS flake (your system config)
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
  - Copies the flake from USB to /mnt/etc/nixos/mandragora
  - Generates hardware-configuration.nix

### 3. Review hardware config

    nvim /mnt/etc/nixos/mandragora/hosts/mandragora-desktop/hardware-configuration.nix

  Verify disk UUIDs and kernel modules look sane.

### 4. Install NixOS

    nixos-install --flake /mnt/etc/nixos/mandragora#mandragora-desktop --no-root-passwd

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

    cd /mnt/etc/nixos/mandragora
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

### Full diagnostic dump

    mandragora-debug

Dumps shell, mounts, credentials, services, dmesg to screen and /tmp/mandragora-debug.log.

### Nothing under /mnt/ventoy

The USB exFAT partition should auto-mount. If empty:

    ls /dev/disk/by-label/                     # is "Ventoy" listed?
    journalctl -u mnt-ventoy.automount --no-pager
    mount -L Ventoy /mnt/ventoy                # manual mount
    ls /mnt/ventoy/

If "Ventoy" label is missing, find the partition manually:

    lsblk -f                                   # look for exfat partition
    mount /dev/sdX1 /mnt/ventoy                # mount it by device

### /persist not mounted (no credentials, no claude)

Persistence requires /mnt/ventoy to be mounted first:

    mount -L Ventoy /mnt/ventoy                # mount USB if needed
    ls /mnt/ventoy/persistence/                # nixos_persistence.dat must exist
    losetup --find --show /mnt/ventoy/persistence/nixos_persistence.dat
    mkdir -p /persist && mount /dev/loopN /persist   # use loop device from above
    ls /persist/                               # should have: claude/ ssh/ npm-global/

Then wire credentials and SSH into your home:

    ln -sfn /persist/npm-global ~/.npm-global
    [ -f /persist/claude/.credentials.json ] && mkdir -p ~/.claude && \
      ln -sfn /persist/claude/.credentials.json ~/.claude/.credentials.json
    [ -d /persist/ssh ] && mkdir -p ~/.ssh && ln -sfn /persist/ssh/* ~/.ssh/

### "command not found: claude" (or gemini/qwen)

AI tools install to /persist/npm-global on first boot with internet.
If persist isn't mounted, fix that first (above). Then:

    export npm_config_prefix="/persist/npm-global"
    export PATH="/persist/npm-global/bin:$PATH"
    npm install -g @anthropic-ai/claude-code @google/gemini-cli @qwen-code/qwen-code

### Claude won't authenticate (no browser)

Credentials must be pre-loaded from the host machine via update-usb.sh.
Check if they're in the persist image:

    ls -la /persist/claude/.credentials.json
    ls -la ~/.claude/.credentials.json         # should be symlink to above

### Can't write to Ventoy partition

    mount -o remount,rw /mnt/ventoy

### nixos-install fails with "flake not found"

Make sure format-drive.sh copied the flake, or clone manually:

    git clone <your-repo-url> /mnt/etc/nixos/mandragora

### Need a package temporarily

    nix shell nixpkgs#<package>
