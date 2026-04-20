# Mandragora Execution Plan: Build Checklist

Check off tasks as they're completed. Reference: [`DECISIONS.md`](DECISIONS.md) for all resolved choices.

## Phase 1: Flake Skeleton & Infrastructure
- [x] **Initialize Git & Flake:** Run `nix flake init` and setup the inputs (`nixpkgs`, `home-manager`, `sops-nix`, `impermanence`).
- [x] **Create Directory Layout:** `mkdir -p hosts/mandragora-desktop modules/{core,desktop,user} snippets/`
- [x] **Host Configuration:** Create `hosts/mandragora-desktop/default.nix` defining the system architecture (`x86_64-linux`), timezone, locale, and importing core modules.
- [x] **Hardware Stub:** Generate or copy a baseline `hardware-configuration.nix` for the B650M motherboard and SFF build.
- [x] **Core Globals:** Define `modules/core/globals.nix` for system-wide constants (e.g., `hostname = "mandragora"`, main user definitions).

## Phase 2: Storage, Impermanence & Core System
- [x] **Btrfs Subvolumes (`fileSystems`):** Explicitly define `/`, `/nix`, `/persistent` with options `compress=zstd:1,noatime,ssd,space_cache=v2`.
- [x] **Impermanence Implementation:** Configure `environment.persistence."/persistent"` binding directories like `/var/log` and `/etc/NetworkManager`.
- [x] **Root Rebuild Service:** Add a `boot.initrd.systemd.services.rollback` script using `btrfs subvolume delete` and `snapshot` to recreate the root pool on boot.
- [x] **Bootloader:** Enable `systemd-boot`, set `boot.initrd.systemd.enable = true`.
- [x] **NVIDIA & Wayland Base:** Set `services.xserver.videoDrivers = ["nvidia"]`, configure `hardware.nvidia` with proprietary beta drivers and `modesetting.enable = true`.

## Phase 3: Desktop Environment & User Management
- [x] **Home Manager Integration:** Setup `home-manager.users.m = import ../../modules/user/home.nix`.
- [x] **Hyprland:** Enable `programs.hyprland.enable = true`. Configure inputs, monitors, and Wayland-specific NVIDIA environment variables.
- [x] **SDDM Login:** Enable `services.displayManager.sddm.wayland.enable = true`.
- [x] **Audio & Network:** Enable PipeWire (`security.rtkit.enable = true`, `services.pipewire.{alsa,pulse,jack}.enable = true`).
- [x] **Dynamic Theming Engine:** Create the wallpaper-to-colors script pipeline in `snippets/` and hook it into Home Manager's Pywal/Stylix configuration.

## Phase 4: Migration & Hardware Control
- [x] **Partitioning Script:** Write the definitive Btrfs+LUKS formatting script in `snippets/format-drive.sh`.
- [x] **Secrets Management:** Setup `sops-nix` with the Age key path (`/persistent/secrets/keys.txt`), configure SSH and user passwords.
- [x] **RGB Control:** Setup `services.hardware.openrgb.enable = true`. Include a startup script for Kingston RAM and MSI cooler.
- [x] **Dotfile Translation:** Convert legacy Arch configs (Polybar -> Waybar, bspwm -> Hyprland).

## Phase 5: The Shadow (Shadow Profile)
- [ ] **LUKS2 Setup:** Create the isolated `/persistent/shadow` container.
- [ ] **Hidden Boot Entry:** Configure systemd-boot to add an alternative generation that unlocks the Shadow volume and loads a separate profile.
- [ ] **Constraint Verification:** Ensure Shadow has no sudo, no terminal execution (or restricted shell), and no AI audits.

## Phase 6: Observability & Polish
- [ ] **Audit Scripts:** Implement `modules/audits/strays.sh` for disk/network monitoring, restricting them to the Mandragora profile.
- [ ] **Seafile/Backup:** Configure Seafile client pointing to the arch-slave.

## Phase 7: Scripts & Local Binaries
- [ ] **Categorize Scripts:** Group scripts in `~/projects/mandragora/.local/bin/` into categories (UI, Media, System, Utils, etc.).
- [ ] **Nixify Binaries:** Convert each script into a Home Manager `home.packages` entry using `pkgs.writeShellScriptBin` or move them to `snippets/` if they are large.
- [ ] **Dependency Mapping:** Identify and declare all external dependencies (e.g., `byzanz`, `xsel`, `ffmpeg`) in Nix.
- [ ] **Cleanup PATH:** Ensure `$HOME/.local/bin` is deprecated in favor of Nix-managed binaries.
