<div align="center">

```
┏┳┓┏━┓┏┓╻╺┳┓┏━┓┏━┓┏━╸┏━┓┏━┓┏━┓
┃┃┃┣━┫┃┗┫ ┃┃┣┳┛┣━┫┃╺┓┃ ┃┣┳┛┣━┫
╹ ╹╹ ╹╹ ╹╺┻┛╹┗╸╹ ╹┗━┛┗━┛╹┗╸╹ ╹
```

[![NixOS Unstable](https://img.shields.io/badge/NixOS-unstable-5277C3?style=for-the-badge&logo=nixos&logoColor=white)](https://nixos.org)
[![Hyprland](https://img.shields.io/badge/Hyprland-Wayland-58E1FF?style=for-the-badge&logo=wayland&logoColor=white)](https://hyprland.org)
[![BMAD](https://img.shields.io/badge/BMAD-METHOD-blueviolet?style=for-the-badge&logo=github&logoColor=white)](https://github.com/bmad-code-org/BMAD-METHOD)
[![Flakes](https://img.shields.io/badge/Nix_Flakes-enabled-7EBAE4?style=for-the-badge&logo=snowflake&logoColor=white)]()
[![Impermanence](https://img.shields.io/badge/Root-ephemeral-FF6B6B?style=for-the-badge)]()
[![sops-nix](https://img.shields.io/badge/Secrets-sops--nix-F5A623?style=for-the-badge&logo=gnuprivacyguard&logoColor=white)](https://github.com/Mic92/sops-nix)

---

**A declarative NixOS workstation that wipes itself clean on every boot.**

*Reproducible from scratch in under 30 minutes. No imperative state. No drift.*

</div>

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  flake.nix                                                      │
│  └── hosts/mandragora-desktop/                                  │
│       ├── hardware-configuration.nix                            │
│       └── default.nix ──┬── modules/core/     System backbone   │
│                         ├── modules/desktop/  Hyprland + gaming │
│                         ├── modules/user/     Home Manager      │
│                         └── modules/audits/   Health checks     │
├─────────────────────────────────────────────────────────────────┤
│  snippets/        Non-Nix logic (shell, Lua, CSS, Python)       │
│  secrets/         Age-encrypted vaults (sops-nix)               │
│  atlas/           Architecture, constraints, partition plan     │
│  appendix/        Self-contained subprojects (Ventoy, WSL)      │
└─────────────────────────────────────────────────────────────────┘
```

## Key Principles

| Principle | Implementation |
|:----------|:---------------|
| **Ephemeral root** | Btrfs snapshot rotation wipes `/` on every boot |
| **Declarative everything** | All state is a Nix expression — zero imperative setup |
| **Language purity** | Non-Nix code lives in `snippets/`, referenced via `builtins.readFile` |
| **Zero plaintext secrets** | sops-nix with age encryption, decryption key on persistent volume |
| **Wayland-only** | Hyprland-based desktop, no X11 fallback |

## Impermanence Lifecycle

```mermaid
flowchart LR
    A["Boot"] --> B["initrd: delete root-active"]
    B --> C["Snapshot root-blank → root-active"]
    C --> D["Mount as /"]
    D --> E["Mount /nix + /persistent"]
    E --> F["System ready"]

    style A fill:#2d2d2d,stroke:#58E1FF,color:#fff
    style B fill:#2d2d2d,stroke:#FF6B6B,color:#fff
    style C fill:#2d2d2d,stroke:#FF6B6B,color:#fff
    style D fill:#2d2d2d,stroke:#58E1FF,color:#fff
    style E fill:#2d2d2d,stroke:#76B900,color:#fff
    style F fill:#2d2d2d,stroke:#76B900,color:#fff
```

## Disk Layout

```mermaid
block-beta
    columns 4
    rb["root-blank\n(seed)"]
    ra["root-active\n(ephemeral)"]
    nix["/nix\n(store)"]
    pers["/persistent\n(state)"]

    style rb fill:#553333,stroke:#FF6B6B,color:#fff
    style ra fill:#553333,stroke:#FF6B6B,color:#fff
    style nix fill:#335533,stroke:#76B900,color:#fff
    style pers fill:#335533,stroke:#76B900,color:#fff
```

## What Survives Reboot

```
     ╭──────────────────────────────────────────────────╮
     │            P E R S I S T E N T                    │
     │                                                  │
     │  /nix ··········· packages, store, generations   │
     │  /persistent/home/m ··········· all user data    │
     │  /persistent/secrets ··········· age key         │
     │  /persistent/var/lib ··········· BT, NixOS       │
     │  /persistent/etc ··········· NM, machine-id      │
     ╰──────────────────────────────────────────────────╯

     ╭──────────────────────────────────────────────────╮
     │            E P H E M E R A L                     │
     │                                                  │
     │  / ··········· wiped every boot                  │
     │  /tmp ··········· tmpfs                          │
     │  /run ··········· tmpfs                          │
     ╰──────────────────────────────────────────────────╯
```

## Module Map

```
modules/
├── core/
│   ├── globals.nix ............. system packages, nix settings
│   ├── boot.nix ................ systemd-boot, kernel params
│   ├── impermanence.nix ........ root wipe + bind mounts
│   ├── persistence.nix ......... declarative persist paths
│   ├── storage.nix ............. Btrfs mounts, fstab
│   ├── graphics.nix ............ Graphics drivers, Wayland env
│   ├── secrets.nix ............. sops-nix declarations
│   ├── security.nix ............ firewall, hardening
│   ├── ai-local.nix ............ Local LLM + acceleration
│   └── vm.nix .................. QEMU/libvirt
├── desktop/
│   ├── hyprland.nix ............ compositor config
│   ├── openrgb.nix ............. peripheral RGB control
│   ├── steam.nix ............... gaming + Proton
│   ├── seafile.nix ............. file sync client
│   └── keyledsd.nix ............ keyboard LEDs
└── user/
    ├── home-manager.nix ........ HM entry point
    ├── home.nix ................ packages, dotfiles
    ├── zsh.nix ................. shell config
    ├── tmux.nix ................ terminal multiplexer
    ├── waybar.nix .............. status bar
    └── lf.nix .................. file manager
```

## Deploy

```bash
sudo nixos-rebuild switch --flake /etc/nixos/mandragora#mandragora-desktop
```

Or use the integrated workflow:

```bash
mandragora-switch "commit message"
```

This stages all changes, rebuilds, and pushes on success — rolling back the commit on failure.

## Flake Inputs

| Input | Purpose |
|:------|:--------|
| [`nixpkgs`](https://github.com/NixOS/nixpkgs) (unstable) | Package set + NixOS modules |
| [`home-manager`](https://github.com/nix-community/home-manager) | Dotfile management as Nix |
| [`sops-nix`](https://github.com/Mic92/sops-nix) | Declarative secret decryption |
| [`impermanence`](https://github.com/nix-community/impermanence) | Stateless root with opt-in persistence |

## Documentation

| Document | Purpose |
|:---------|:--------|
| [`DECISIONS.md`](DECISIONS.md) | All resolved technical choices |
| [`STRUCTURE.md`](STRUCTURE.md) | Repo layout and module map |
| [`DATA_HIERARCHY.md`](DATA_HIERARCHY.md) | 5-tier persistence/backup matrix |
| [`WORKFLOW.md`](WORKFLOW.md) | Sync ritual and rebuild workflow |
| [`SECRETS.md`](SECRETS.md) | sops-nix vault strategy |
| [`atlas/`](atlas/) | Architecture, constraints, partition plan |

---

<div align="center">

*Built with obsessive declarativity on NixOS unstable.*

</div>
