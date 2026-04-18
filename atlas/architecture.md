# Architecture Document: Mandragora NixOS

## 1. System Overview
*   **Operating System:** NixOS (Flake-based, purely declarative).
*   **Bootloader:** systemd-boot.
*   **Compositor:** Hyprland (Wayland native).
*   **Login Manager:** SDDM.
*   **Kernel:** `linuxPackages_zen` (optimized for DRM and Zen 4 scheduler tweaks).

## 2. Storage & Partitioning Strategy (2TB NVMe)
The system utilizes a Btrfs-heavy layout optimized for impermanence and strict profile isolation.

*   **ESP (`/boot`):** 4GB FAT32 (~30 boot generations).
*   **Swap:** 32GB (hibernation).
*   **Btrfs Pool (NIXOS, ~1.9TB):** All subvolumes share this single partition.
    *   `root-blank`: Clean seed for impermanence wipe (never mounted).
    *   `root-active` → `/`: Ephemeral root, wiped on boot.
    *   `nix` → `/nix`: Nix store, packages, generations.
    *   `persistent` → `/persistent`: Home, secrets, system state.
*   **Shadow:** `/persistent/shadow.img` (50GB LUKS2 loop → `/home/shadow`).

## 3. Impermanence & State Management
*   **Philosophy:** "Erase your darlings" — root partition is wiped/restored, ensuring no lingering imperative state.
*   **Mechanism:** systemd initrd service deletes `root-active` and snapshots `root-blank` → `root-active` on every boot. The `impermanence` module bind-mounts persistent state from `/persistent`.

## 4. Graphics, Display, and Theming Pipeline
*   **Hardware Stack:** NVIDIA RTX 5070 Ti (Proprietary 570.x drivers) + Wayland (GBM backend). Strict "No X11 Fallback" policy for the desktop session.
*   **Race Condition Mitigation:** Due to a known race condition between Plymouth, NVIDIA 570.x, and SDDM on Wayland, the animated Plymouth splash screen is **excluded** from the initial build phase. Boot sequence goes directly from firmware splash to SDDM.
*   **Theming Engine:** Pywal-style dynamic palette. A source wallpaper drives color extraction, generating a `colors.json` that injects variables into Hyprland, Kitty, Neovim, Waybar, and GTK via Home Manager.

## 5. Security & Secrets
*   **Secrets Management:** `sops-nix` using the **Age** format. The master key file resides on an external USB drive (backed up to Seafile/Oracle VPS). No plain-text secrets are committed to the git repository.
*   **Encryption:** LUKS2 for the isolated Shadow profile only (loop-mounted image file).

## 6. Codebase Structure & Language Purity
*   **Repository Layout:** Standard flake architecture (`flake.nix`, `hosts/`, `modules/`).
*   **Hardware Config:** `hardware-configuration.nix` is generated natively at install time and committed directly.
*   **External Snippets:** To maintain Nix language purity, all non-Nix logic (e.g., Python monitoring scripts, Shell partitioners) are housed in `snippets/` and imported/referenced by the Nix configuration.
