<div align="center">

# `mandragora`

[![NixOS](https://img.shields.io/badge/NixOS-unstable-5277C3?style=flat-square&logo=nixos&logoColor=white)](https://nixos.org)
[![Hyprland](https://img.shields.io/badge/Hyprland-Wayland-58E1FF?style=flat-square&logo=wayland&logoColor=white)](https://hyprland.org)
[![Flakes](https://img.shields.io/badge/flakes-enabled-7EBAE4?style=flat-square&logo=snowflake&logoColor=white)]()
[![Impermanent](https://img.shields.io/badge/root-ephemeral-FF6B6B?style=flat-square)]()
[![sops-nix](https://img.shields.io/badge/secrets-sops--nix-F5A623?style=flat-square&logo=gnuprivacyguard&logoColor=white)](https://github.com/Mic92/sops-nix)

<img src="docs/assets/readme/demo.gif" width="900" alt="mandragora desktop demo" />

</div>

[demo.mvr.ac](https://demo.mvr.ac)

---

Declarative NixOS workstation — a "second skin" Linux environment built
for one machine, one user, and total comprehensibility. The root
filesystem is **impermanent** (wiped every boot; only `/nix`,
`/persistent`, and `/home/m` survive), the desktop is **Hyprland on
proprietary NVIDIA / Wayland** with no X11 fallback, secrets are
sops-nix + age, and the whole thing is a **multi-host flake** that also
carries a WSL profile, a bootable rescue USB, and an Oracle VPS.

## Hosts

| Host | Purpose |
| ---- | ------- |
| `mandragora-desktop` | Primary Ryzen 9 7900X / RTX 5070 Ti workstation — Hyprland, impermanent Btrfs root, full ricing pipeline |
| `mandragora-wsl` | Same profile under WSL2 — corporate-laptop fallback ([`docs/appendix/wsl/README.md`](docs/appendix/wsl/README.md)) |
| `mandragora-usb` | Bootable installer / rescue image — `nix build .#usbImage`, test-driven via `nix run .#refiner -- --auto` |
| `mandragora-vps` | Oracle Cloud aarch64 VPS — **not NixOS**; home-manager + Docker Compose stacks behind a Caddy proxy ([`nix/hosts/mandragora-vps/INVENTORY.md`](nix/hosts/mandragora-vps/INVENTORY.md)) |

## Workflow

```
Edit    nix/... or XDG-mirrored config at repo root
Rebuild mandragora-switch [msg]   # commit + nixos-rebuild switch + push
Verify  test the changed feature directly — there is no unit test suite
```

Full common-tasks reference and aliases: [`docs/workflow.md`](docs/workflow.md).

## Audits

A deterministic, errors-only shell suite (`mandragora-audit`) enforces the
repo invariants — language purity, doc-link integrity, hub tiles, hyprland
syntax, `nixfmt-rfc-style` formatting, shellcheck, and more — as a
pre-commit gate. Detail: [`docs/audits.md`](docs/audits.md).

## Docs

Start at the documentation router [`docs/index.md`](docs/index.md); every
survivor doc is one hop from there. Architecture overview lives in
[`docs/architecture.md`](docs/architecture.md).

AI agents (Claude Code, Gemini, local LLMs) read [`AGENTS.md`](AGENTS.md)
first — it holds the non-negotiables, file-safety rules, and per-agent
policy variances.

---

<div align="center">

> *If a system is to serve the creative spirit, it must be entirely
> comprehensible to a single individual.*

</div>
