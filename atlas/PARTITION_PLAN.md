# Mandragora Partition Plan: 2TB NVMe

## Disk: Kingston NV3 PCIe 4.0 (2TB)

| Partition | Size | Filesystem | Purpose |
|-----------|------|------------|---------|
| ESP | 4GB | FAT32 | Boot loader (~30 generations) |
| NIXOS | ~1.9TB | Btrfs (`compress=zstd:1`) | All subvolumes share this pool |
| swap | 32GB | swap | Hibernation |

## Btrfs Subvolume Layout (inside NIXOS)

| Subvolume | Mounted at | Purpose |
|-----------|-----------|---------|
| `root-blank` | *(never mounted)* | Clean seed for impermanence wipe |
| `root-active` | `/` | Ephemeral root, wiped on every boot |
| `nix` | `/nix` | Nix store, packages, generations |
| `persistent` | `/persistent` | Home, secrets, system state |

All subvolumes share the ~1.9TB pool. No fixed allocations.

### What lives in `/persistent`
- `/persistent/home/m` — all user data (~500GB)
- `/persistent/secrets/` — age key for sops-nix
- `/persistent/shadow.img` — 50GB LUKS2 loop → `/home/shadow`
- `/persistent/var/log` — system logs
- `/persistent/var/lib/nixos` — NixOS state
- `/persistent/etc/NetworkManager/system-connections` — wifi credentials
- `/persistent/etc/machine-id` — stable systemd machine identity

## Boot Configuration

- **Boot loader:** systemd-boot
- **Recovery:** Hold **Space** during boot for generation menu; default boots instantly (`timeout 0`)
- **Initrd:** systemd-based (`boot.initrd.systemd.enable = true`)
- **Impermanence:** A systemd initrd service deletes `root-active` and snapshots `root-blank` → `root-active` before mounting

## Display Server
- **Compositor:** Hyprland (Wayland-native, GBM backend for NVIDIA)
- **Login manager:** SDDM
- **Audio:** PipeWire
- **Browser:** Firefox (Wayland-native, Home Manager-managed extensions)
- **RGB:** OpenRGB + liquidctl
- **Theming:** Pywal-style dynamic palette (planned)

## Nix Store Policy
- `/nix` survives reboots (dedicated subvolume)
- Nix GC: weekly, deletes older than 7 days
- Boot generations: 10 max (`configurationLimit`)

## Kernel
- `linuxPackages_zen`

## Network
- **Primary:** Ethernet (RJ45)
- **Fallback:** WiFi 6E (motherboard built-in)

## Notes
- `/persistent` is plain Btrfs — no encryption.
- Shadow data is encrypted via LUKS2 loop-mounted image file inside `/persistent`.
- Swap supports hibernation.
- Install sequence is fully scripted in `snippets/INSTALL.md`.
