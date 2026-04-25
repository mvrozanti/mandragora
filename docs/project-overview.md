# mandragora-nixos — Project Overview

**Date:** 2026-04-25
**Type:** infra (declarative system configuration)
**Architecture:** Single-host NixOS flake with modular composition

## Executive Summary

`mandragora-nixos` is the complete, declarative system configuration for the
Mandragora workstation — a single-host NixOS flake that defines the OS, the
desktop environment, the user home, and every service that runs on the
machine. The repository is the source of truth: the box itself is disposable
because the root filesystem is wiped on every boot (impermanence), and only
`/nix`, `/persistent`, and `/home/m` survive. Reproducing the workstation from
scratch is a single `nixos-install --flake` away.

The codebase migrates a long-running Arch + bspwm rice into NixOS while
preserving the user's hand-tuned ergonomics (Hyprland keybindings, theming
pipeline, mpd/ncmpcpp, lf, neovim, tmux, zsh). It is intentionally a
single-user, single-machine configuration — not a generic "NixOS for everyone"
template.

## Project Classification

- **Repository Type:** monolith
- **Project Type:** infra (NixOS flake, system configuration as code)
- **Primary Language:** Nix (with Bash, Python, Lua, CSS as XDG-mirrored
  external snippets)
- **Architecture Pattern:** Modular flake — `flake.nix` → host →
  `modules/{core,desktop,user}/<concern>.nix`

## Technology Stack Summary

| Category            | Technology                          | Version / Source                       | Justification                                                  |
| ------------------- | ----------------------------------- | -------------------------------------- | -------------------------------------------------------------- |
| OS                  | NixOS                               | nixpkgs `nixos-unstable`               | Declarative, reproducible, rolling                             |
| Bootloader          | systemd-boot                        | system default                         | Simple, no GRUB                                                |
| Kernel              | `linuxPackages_zen`                 | nixpkgs                                | Zen 4 scheduler tweaks, DRM-friendly                           |
| Filesystem          | Btrfs                               | kernel                                 | Subvolumes for impermanence, snapshots                         |
| Compositor          | Hyprland                            | nixpkgs                                | Wayland-native, scriptable, animation-rich                     |
| Display Manager     | SDDM                                | nixpkgs                                | Wayland-capable, theme-friendly                                |
| GPU                 | NVIDIA proprietary                  | 570.x beta                             | RTX 5070 Ti requires modern proprietary stack                  |
| Secrets             | sops-nix + age                      | github:Mic92/sops-nix                  | Zero plain-text secrets in git                                 |
| User home           | home-manager                        | nix-community, follows nixpkgs         | Declarative user config                                        |
| Impermanence        | impermanence                        | nix-community                          | Wipe `/` each boot, bind-mount persistent paths                |
| Shell               | zsh                                 | nixpkgs                                | User preference, plugins declared in Nix                       |
| Terminal multiplexer | tmux                               | nixpkgs                                | Plugins declared via `programs.tmux.plugins`                   |
| Editor              | neovim                              | nixpkgs                                | Plugins declared via home-manager                              |
| Music               | mpd + ncmpcpp                       | nixpkgs                                | Local library playback                                         |
| Bar                 | waybar                              | nixpkgs                                | Wayland status bar                                             |
| Theming             | pywal-style dynamic palette         | custom (`snippets/`)                   | Wallpaper-driven colors → Hypr/Kitty/Waybar/Neovim             |

## Key Features

- **Impermanence by design** — root is wiped every boot; only declared
  persistent paths survive. The git remote (`mandragora-nixos`) is the
  persistence mechanism for the configuration source itself.
- **Strict language purity** — no shell/CSS/Lua/Python embedded inside `.nix`
  files. Non-Nix code lives at the repo root in XDG-mirrored directories
  (`.config/`, `.local/bin/`, `snippets/`) and is referenced via
  `builtins.readFile` or `pkgs.writeShellScript`.
- **Out-of-the-box** — every program added must work from first launch with
  zero setup. No plugin managers that bootstrap on first run; no first-run
  wizards.
- **Zero plain-text secrets** — sops-nix with age encryption; the master key
  lives at `/persistent/secrets/keys.txt`.
- **NVIDIA + Wayland only** — no X11 fallback. The constraint is firm.
- **No FDE** — main drive is intentionally unencrypted.
- **One concern per module** — `modules/<area>/<thing>.nix`. Modules don't
  exceed one screen of code.

## Architecture Highlights

- **Flake entry:** `flake.nix` defines a single `nixosConfigurations.mandragora-desktop` output that pulls `nixpkgs`, `home-manager`, `sops-nix`, and `impermanence` as inputs.
- **Host composition:** `hosts/mandragora-desktop/default.nix` imports every module from `modules/{core,desktop,user}/` and `pkgs/overlays.nix`.
- **Boot lifecycle:** systemd initrd service deletes the `root-active` Btrfs
  subvolume and snapshots `root-blank` → `root-active` on each boot, giving a
  clean root every cycle.
- **Theming pipeline:** a source wallpaper drives pywal-style color
  extraction; the resulting palette is injected into Hyprland, Kitty, Neovim,
  Waybar, and GTK via home-manager-managed templates.
- **Secrets path:** `secrets/secrets.yaml` (age-encrypted) →
  `modules/core/secrets.nix` → `config.sops.secrets."<path>".path` references
  inside other modules.

## Development Overview

### Prerequisites

- The machine itself running NixOS (or a NixOS install medium for first-time
  install).
- `git`, `nix` with flakes and `nix-command` enabled.
- `sops` and the age private key at `/persistent/secrets/keys.txt` (for
  decrypting secrets during builds).
- Sudo access on the machine to run `nixos-rebuild switch`.

### Getting Started

The repo lives at two paths simultaneously:

- `/etc/nixos/mandragora/` — the canonical path consumed by `nixos-rebuild`.
- `/persistent/mandragora/` — the same git working tree (bind-mounted).

Both point at the same files. Edit anywhere; commit anywhere.

### Key Commands

- **Edit:** open any file under `modules/`, `hosts/`, `.config/`, `.local/bin/`, or `snippets/`.
- **Rebuild:** `sudo nixos-rebuild switch --flake /etc/nixos/mandragora#mandragora-desktop`
- **Verify:** test the changed feature directly (no test suite — verification
  is empirical).
- **Commit + push:** `git add -A && git commit && git push` — or use the
  `mandragora-switch` zsh alias (rebuild + git sync wrapper).
- **Temporary package without rebuild:** `nix shell nixpkgs#<pkg>` — ephemeral
  shell, follow up by adding the package to `modules/core/globals.nix`.

## Repository Structure (Summary)

```
flake.nix                  # entry point — defines mandragora-desktop config
hosts/mandragora-desktop/  # host-specific composition + hardware-configuration
modules/core/              # OS-level: boot, storage, impermanence, secrets, security, monitoring, AI
modules/desktop/           # GUI/Wayland: Hyprland, kdeconnect, keyledsd, openrgb, steam, etc.
modules/user/              # home-manager: home.nix, zsh, tmux, waybar, lf, services
modules/audits/            # housekeeping checks for stray imperative state
.config/                   # XDG-mirrored app configs (Hypr, mpd, mpv, tmux, waybar, nvim, etc.)
.local/bin/                # user shell scripts referenced via builtins.readFile
snippets/                  # Python/Lua/CSS helpers and waybar/keyledsd scripts
pkgs/                      # local overlays + custom packages (claude-code, du-exporter, rtk)
secrets/                   # sops-encrypted secrets.yaml
install/                   # bootstrap scripts (format-drive, mount-install, install.sh)
atlas/                     # high-level design docs (architecture, hardware, software, PRD, decisions)
docs/                      # this directory — generated docs and AI context
```

For the detailed annotated tree, see [source-tree-analysis.md](./source-tree-analysis.md).

## Documentation Map

For detailed information, see:

- [index.md](./index.md) — Master documentation index
- [architecture.md](./architecture.md) — Detailed technical architecture
- [source-tree-analysis.md](./source-tree-analysis.md) — Annotated directory structure
- [development-guide.md](./development-guide.md) — Edit → Rebuild → Verify → Commit workflow
- [deployment-guide.md](./deployment-guide.md) — Bootstrap and reinstall procedure
- [project-context.md](./project-context.md) — LLM-optimized rules distillate (canonical for AI)

Upstream design references:

- `../AGENTS.md` — hard constraints (canonical)
- `../CLAUDE.md` — Claude Code-specific addendum
- `../DECISIONS.md` — resolved choices log
- `../atlas/architecture.md`, `../atlas/hardware.md`, `../atlas/software.md`, `../atlas/PRD.md`

---

_Generated using BMAD Method `document-project` workflow._
