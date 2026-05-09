<div align="center">

# `mandragora`

*the second skin*

[![NixOS](https://img.shields.io/badge/NixOS-unstable-5277C3?style=flat-square&logo=nixos&logoColor=white)](https://nixos.org)
[![Hyprland](https://img.shields.io/badge/Hyprland-Wayland-58E1FF?style=flat-square&logo=wayland&logoColor=white)](https://hyprland.org)
[![Flakes](https://img.shields.io/badge/flakes-enabled-7EBAE4?style=flat-square&logo=snowflake&logoColor=white)]()
[![Impermanent](https://img.shields.io/badge/root-ephemeral-FF6B6B?style=flat-square)]()
[![sops-nix](https://img.shields.io/badge/secrets-sops--nix-F5A623?style=flat-square&logo=gnuprivacyguard&logoColor=white)](https://github.com/Mic92/sops-nix)

<img src="assets/readme/waybar.png" width="900" alt="waybar — mpd, hardware vitals, network, weather, actions" />

</div>

A single-host NixOS flake. One machine. One user. One source of truth.

Fifteen years of Arch+bspwm distilled into a declarative expression. Root is wiped on every boot; what survives is what is written down.

> **45 modules · 8 in-tree packages · 4 hosts · ephemeral root · zero plain-text secrets**
> Ryzen 9 7900X · RTX 5070 Ti · 32 GB DDR5 — full spec in [`docs/hardware.md`](docs/hardware.md)

### what's interesting in here

  [`gpu-lock`](pkgs/gpu-lock.nix) · cooperative GPU arbitration across agents — non-blocking, respect-the-holder, with a VRAM-cleanup contract on release
  [`mandragora-switch`](.local/bin/mandragora-switch.sh) · rebuild + AI-generated commit message (Gemini → Claude Haiku → editor) + concurrent-edit guard + auto-rollback
  [`modules/audits/`](modules/audits/) · weekly CVE scan (vulnix), repo pre-commit checks, USB-closure size guard, sops-key encryption guard
  [`hosts/`](hosts/) · same flake, four targets — `desktop`, `usb` (templated installer with sops decrypt + hardware sniffing), `vps`, `wsl`
  [`agent-skills/`](agent-skills/) · handoff/pickup baton-pass, gpu-lock contract, hotkey audit — symlinked into both `.claude/` and `.gemini/`
  [`ai-local`](modules/core/ai-local.nix) + [`bots`](modules/user/bots.nix) · Ollama on CUDA + telegram bots (Flux image-gen, LLM chat), all serialized through gpu-lock

### impermanence

```mermaid
flowchart LR
    A["boot"] --> B["initrd: delete root-active"]
    B --> C["snapshot root-blank → root-active"]
    C --> D["mount as /"]
    D --> E["mount /nix + /persistent"]
    E --> F["ready"]

    style A fill:#1a1a1a,stroke:#58E1FF,color:#fff
    style B fill:#1a1a1a,stroke:#FF6B6B,color:#fff
    style C fill:#1a1a1a,stroke:#FF6B6B,color:#fff
    style D fill:#1a1a1a,stroke:#58E1FF,color:#fff
    style E fill:#1a1a1a,stroke:#76B900,color:#fff
    style F fill:#1a1a1a,stroke:#76B900,color:#fff
```

  Survives reboot — `/nix`, `/persistent`, `/home/m` (bind-mounted). Everything else is ash.

### deploy

```sh
mandragora-switch "feat(scope): description"
```

  Stages, rebuilds, commits, pushes. Rolls back on failure. Falls back to AI-generated commit messages when run with no argument. flock + working-tree stability window protect against concurrent agents.

### map

  `flake.nix`         the root
  `hosts/`            per-host composition (desktop · usb · vps · wsl)
  `modules/`          one concern each — `core/` `desktop/` `user/` `audits/`
  `pkgs/`             in-tree derivations
  `docs/`             the long form

### further

  [`AGENTS.md`](AGENTS.md) · the charter — load first for any AI session
  [`docs/index.md`](docs/index.md) · doc router
  [`docs/architecture.md`](docs/architecture.md) · composition, modules, audits
  [`install/INSTALL.md`](install/INSTALL.md) · fresh-install runbook

---

<div align="center">

> *If a system is to serve the creative spirit, it must be entirely
> comprehensible to a single individual.*

</div>
