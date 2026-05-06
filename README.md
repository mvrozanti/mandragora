<div align="center">

# `mandragora`

*the second skin*

[![NixOS](https://img.shields.io/badge/NixOS-unstable-5277C3?style=flat-square&logo=nixos&logoColor=white)](https://nixos.org)
[![Hyprland](https://img.shields.io/badge/Hyprland-Wayland-58E1FF?style=flat-square&logo=wayland&logoColor=white)](https://hyprland.org)
[![Flakes](https://img.shields.io/badge/flakes-enabled-7EBAE4?style=flat-square&logo=snowflake&logoColor=white)]()
[![Impermanent](https://img.shields.io/badge/root-ephemeral-FF6B6B?style=flat-square)]()
[![sops-nix](https://img.shields.io/badge/secrets-sops--nix-F5A623?style=flat-square&logo=gnuprivacyguard&logoColor=white)](https://github.com/Mic92/sops-nix)

</div>

---

A single-host NixOS flake. One machine. One user. One mind.

Fifteen years of Arch+bspwm, distilled into a declarative expression that
rebuilds itself byte-for-byte from this repo. The root filesystem is wiped
on every boot; what survives is what is written down.

---

### hardware

```
   cpu    Ryzen 9 7900X            12C / 24T   5.6 GHz   170 W
   gpu    RTX 5070 Ti  Windforce   16 GB GDDR7  Blackwell
   ram    32 GB DDR5-6000 CL30     Kingston Fury  EXPO v1.1
   mobo   B650M AORUS ELITE AX     mATX  PCIe 5.0
   nvme   Kingston NV3 2 TB        PCIe 4.0
   aio    MSI MAG Coreliquid A13   360 mm  ARGB
   psu    Toughpower GF A3 850 W   ATX 3.0  12V-2x6
   case   Lian Li A3-mATX          26.3 L
```

### stack

  Hyprland · Wayland · NVIDIA 570 (open) · zen kernel · Btrfs · systemd-boot
  · home-manager · sops-nix · impermanence · Ollama · Tailscale · Prometheus + Grafana

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

  Survives reboot — `/nix`, `/persistent`, `/home/m` (bind-mounted).
  Everything else is ash.

### deploy

```sh
mandragora-switch "feat(scope): description"
```

  Stages, rebuilds, commits, pushes. Rolls back on failure.
  flock + working-tree stability window protect against concurrent agents.

### map

  `flake.nix`              the root
  `hosts/mandragora-desktop/`  composition
  `modules/{core,desktop,user,audits}/`  37 modules, one concern each
  `pkgs/`                  in-tree derivations — `rtk`, `gpu-lock`, `sddm-mandragora`, `du-exporter`, …
  `snippets/`              non-Nix code (shell, lua, css, python) referenced via `readFile`
  `secrets/`               sops-nix vaults, age-encrypted
  `docs/`                  the long form

### further

  [`AGENTS.md`](AGENTS.md) · the charter — load first for any AI session
  [`docs/index.md`](docs/index.md) · doc router
  [`docs/architecture.md`](docs/architecture.md) · composition, modules, audits
  [`docs/hardware.md`](docs/hardware.md) · build, peripherals, NVIDIA tuning
  [`docs/workflow.md`](docs/workflow.md) · edit → rebuild → verify → commit
  [`docs/persistence.md`](docs/persistence.md) · what survives reboot
  [`docs/secrets.md`](docs/secrets.md) · sops-nix + age
  [`docs/gpu.md`](docs/gpu.md) · respect-the-holder GPU contract
  [`docs/worktrees.md`](docs/worktrees.md) · parallel-agent isolation
  [`install/INSTALL.md`](install/INSTALL.md) · fresh-install runbook

---

<div align="center">

> *If a system is to serve the creative spirit, it must be entirely
> comprehensible to a single individual.*

</div>
