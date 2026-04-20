# Mandragora Decisions: Resolved Technical Choices

Every resolved choice for the `mandragora-desktop` build. If it's not here, it's undecided.

---

## Identity

| Decision | Value |
|----------|-------|
| Hostname | `mandragora-desktop` |
| Username | `m` |
| Git name | `Marcelo` |
| Git email | `mvrozanti@hotmail.com` |
| NixOS channel | `nixos-unstable` |

---

## Boot & Impermanence

| Decision | Value |
|----------|-------|
| Boot loader | systemd-boot (plain, no Secure Boot) |
| Recovery | Hold **Space** during boot for generation menu; default boots instantly (`timeout 0`) |
| Initrd | systemd-based (`boot.initrd.systemd.enable = true`) |
| Kernel | `linuxPackages_zen` |
| Impermanence mechanism | Systemd initrd service deletes `root-active`, snapshots `root-blank` → `root-active` on every boot |
| `/nix/store` | Survives reboots (dedicated subvolume) |
| Nix GC | Weekly, deletes older than 7 days, 10 boot generations max |

---

## Disk Layout

Full details in [`atlas/PARTITION_PLAN.md`](atlas/PARTITION_PLAN.md).

| Partition | Size | Filesystem | Purpose |
|-----------|------|------------|---------|
| ESP | 4GB | FAT32 | Boot loader (~30 generations) |
| NIXOS | ~1.9TB | Btrfs (`compress=zstd:1`) | All subvolumes share this pool |
| swap | 32GB | swap | Hibernation |

### Btrfs Subvolumes (inside NIXOS partition)

| Subvolume | Mounted at | Purpose |
|-----------|-----------|---------|
| `root-blank` | *(never mounted)* | Clean seed for impermanence wipe |
| `root-active` | `/` | Ephemeral root, wiped on boot |
| `nix` | `/nix` | Nix store, packages, generations |
| `persistent` | `/persistent` | Home, secrets, system state |

Second profile details: see SHADOW.md

---

## Persistence Map

### User State (survives via `/persistent/home`)
All of `/home/m` persists, including: `~/.ssh/`, `~/.gnupg/`, `~/.config/`, `~/.local/share/seafile/`, `~/.mozilla/`, `~/.steam/`, `~/.cache/`, `~/.local/state/`

### System State (survives via `/persistent/etc` and `/persistent/var/lib`)
`/etc/NetworkManager/system-connections/`, `/etc/ssh/ssh_host_*`, `/etc/machine-id`, `/var/lib/NetworkManager/`, `/var/lib/bluetooth/`, `/var/lib/nixos/`

### Ephemeral (destroyed every boot)
`/` (root), `/tmp` (tmpfs), `/run` (tmpfs)

### Deferred
Backups and arch-slave sync logic — designed after the system is running.

---

## Display & Desktop

| Decision | Value |
|----------|-------|
| Compositor | Hyprland (Wayland, GBM backend for NVIDIA) |
| Login manager | SDDM |
| Audio | PipeWire |
| Browser | Firefox (Wayland-native, Home Manager extensions) |
| Terminal | Kitty (migrate existing config) |
| Shell | zsh |
| Font | IosevkaTerm Nerd Font Mono |
| Status bar | Waybar (translate Polybar config later) |
| Theming | Pywal-style dynamic palette (`colors.json`) |
| Gaming | Steam + Wine + Proton pre-configured |
| Flatpak | No. Nix-only, period. |
| Package manager philosophy | Nix-only. `nix shell` for temporary, `home.packages` for permanent. |

---

## Hardware & Peripherals

| Decision | Value |
|----------|-------|
| NVIDIA driver | `nvidiaPackages.beta` from `nixos-unstable` (570.x branch) |
| RGB control | OpenRGB + liquidctl from userspace |
| Primary network | Ethernet (RJ45), zero config |
| Fallback network | WiFi 6E (motherboard built-in), SSID/passphrase in flake |
| Install media | Standard NixOS ISO |
| Partitioning | Script in `snippets/` handles partitioning, formatting, subvolume creation, mounting. Stops there. Manual `nixos-install` and flake clone. |
| WiFi setup at store | Manual `iwctl` at live USB prompt |
| SSH keys | Migrate from Arch reference machine via LAN (post-install) |

---

## Secrets

| Decision | Value |
|----------|-------|
| Management | sops-nix |
| Key format | age |
| `secrets/` location | Eventually on dedicated USB drive; for now in-repo via sops-nix |

---

## External Systems

| System | Relationship |
|--------|-------------|
| `arch-slave` | Reference machine + bulk storage + Seafile server. Stays Arch + pacman. Not managed by this flake. Seafile runs here; Mandragora connects as a client. Backup logic lives in Mandragora Nix config (push, not pull). |
| Oracle VPS | Future use. Not currently hosting Seafile. |
| Notebook | Future host. Not yet defined. |
