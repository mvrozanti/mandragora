# mandragora-nixos Documentation Index

**Type:** monolith (single-host NixOS flake)
**Primary Language:** Nix (with Bash, Python, Lua, CSS as XDG-mirrored snippets)
**Architecture:** Modular flake — `flake.nix` → host → `modules/{core,desktop,user,audits}/<concern>.nix`
**Last Updated:** 2026-04-25

## Project Overview

`mandragora-nixos` is the complete declarative system configuration for the
Mandragora workstation — a single host (`mandragora-desktop`), single user
(`m`), single nixosConfiguration. Every runtime concern is expressed as a
Nix module under `modules/`. The host's root filesystem is wiped on every
boot (impermanence); only `/nix`, `/persistent`, and `/home/m` survive. The
git remote is the persistence mechanism for the configuration source.

## Quick Reference

- **Tech Stack:** NixOS (`nixos-unstable`), Hyprland/Wayland, NVIDIA proprietary 570.x, Btrfs + impermanence, sops-nix + age, home-manager
- **Entry Point:** `flake.nix` → `nixosConfigurations.mandragora-desktop` → `hosts/mandragora-desktop/default.nix`
- **Architecture Pattern:** Modular flake, one concern per module, language purity (non-Nix code in XDG-mirrored dirs)
- **Hardware:** AMD Ryzen 9 7900X, RTX 5070 Ti 16 GB, 32 GB DDR5, 2 TB NVMe
- **Deployment:** `sudo nixos-rebuild switch --flake /etc/nixos/mandragora#mandragora-desktop`

## Generated Documentation

### Core Documentation

- [Project Overview](./project-overview.md) — Executive summary and high-level architecture
- [Source Tree Analysis](./source-tree-analysis.md) — Annotated directory structure
- [Architecture](./architecture.md) — Detailed technical architecture (storage, impermanence, secrets, theming, modules)
- [Development Guide](./development-guide.md) — Edit → Rebuild → Verify → Commit workflow
- [Deployment Guide](./deployment-guide.md) — In-place rebuild and fresh-install procedure

### AI Context

- **Load first:** [`../AGENTS.md`](../AGENTS.md) — canonical hard constraints, workflow, AI bridge, per-agent policy variances.
- Then your agent's delta: [`../CLAUDE.md`](../CLAUDE.md) (Claude Code), [`../GEMINI.md`](../GEMINI.md) (Gemini CLI).
- [project-context.md](./project-context.md) — _retired 2026-04-25; now a pointer to AGENTS.md_

### Plans & Specs (`superpowers/`)

#### Plans

- [2026-04-21-directory-monitoring.md](./superpowers/plans/2026-04-21-directory-monitoring.md) — Grafana + Prometheus monitoring stack implementation plan
- [2026-04-21-wallpaper-picker.md](./superpowers/plans/2026-04-21-wallpaper-picker.md) — QuickShell wallpaper picker + matugen migration plan

#### Specs

- [2026-04-21-directory-monitoring-design.md](./superpowers/specs/2026-04-21-directory-monitoring-design.md) — Monitoring design spec (approved)
- [2026-04-21-tmux-powerline-design.md](./superpowers/specs/2026-04-21-tmux-powerline-design.md) — tmux-powerline integration design
- [2026-04-21-wallpaper-picker-design.md](./superpowers/specs/2026-04-21-wallpaper-picker-design.md) — Wallpaper picker design spec (approved)

## Existing Documentation (Repo Root)

These are the human-facing reference documents at the repo root and in
`atlas/`. They are upstream sources of truth — generated docs in this
directory are derived from them or complement them.

- [`../AGENTS.md`](../AGENTS.md) — **Canonical hard constraints** (load first for any AI session)
- [`../CLAUDE.md`](../CLAUDE.md) — Claude Code-specific addendum
- [`../GEMINI.md`](../GEMINI.md) — Gemini-specific addendum
- [`../DECISIONS.md`](../DECISIONS.md) — Resolved-choices log
- [`../README.md`](../README.md) — Reader-facing summary
- [`../STRUCTURE.md`](../STRUCTURE.md) — High-level orientation
- [`../WORKFLOW.md`](../WORKFLOW.md) — Workflow notes
- [`../SESSIONS.md`](../SESSIONS.md) — Append-only session log
- [`../FRICTION_LOG.md`](../FRICTION_LOG.md) — Open issues
- [`../SITUATIONS.md`](../SITUATIONS.md) — Runbook scenarios
- [`../SECRETS.md`](../SECRETS.md) — Secrets wiring notes
- [`../DATA_HIERARCHY.md`](../DATA_HIERARCHY.md) — `/persistent` layout and bind-mounts
- [`../EXECUTION_PLAN.md`](../EXECUTION_PLAN.md) — Outstanding work roadmap
- [`../atlas/architecture.md`](../atlas/architecture.md) — Human-facing architecture overview
- [`../atlas/hardware.md`](../atlas/hardware.md) — Hardware specs and quirks
- [`../atlas/software.md`](../atlas/software.md) — Software inventory + rationale
- [`../atlas/PRD.md`](../atlas/PRD.md) — Product Requirements Document
- [`../atlas/PARTITION_PLAN.md`](../atlas/PARTITION_PLAN.md) — Disk partition design
- [`../atlas/non-negotiables.md`](../atlas/non-negotiables.md) — Hard constraints landmark (canonical: AGENTS.md)
- [`../atlas/OPEN_DECISIONS.md`](../atlas/OPEN_DECISIONS.md) — Pending decisions
- [`../atlas/TODO.md`](../atlas/TODO.md) — Outstanding work
- [`../install/INSTALL.md`](../install/INSTALL.md) — Fresh-install runbook

## Getting Started

### As a User (Day-to-Day)

```bash
# Edit a module
$EDITOR /etc/nixos/mandragora/modules/core/globals.nix

# Rebuild
sudo nixos-rebuild switch --flake /etc/nixos/mandragora#mandragora-desktop

# Commit
cd /etc/nixos/mandragora && git add -A && git commit && git push

# (Or use the alias that automates rebuild + commit + push)
mandragora-switch
```

### As a Fresh Installer

See [deployment-guide.md](./deployment-guide.md) and
[`../install/INSTALL.md`](../install/INSTALL.md).

### Add a Package

- System-wide: `modules/core/globals.nix` → `environment.systemPackages`
- User-only: `modules/user/home.nix` → `home.packages`
- Temporary (try before committing): `nix shell nixpkgs#<pkg>`

## For AI-Assisted Development

This documentation is generated specifically to enable AI agents to
understand and extend this codebase. Load [`../AGENTS.md`](../AGENTS.md)
first — it is the canonical statement of hard constraints, workflow, AI
bridge, and per-agent policy variances. Then load your agent's delta file
(`../CLAUDE.md` for Claude Code, `../GEMINI.md` for Gemini CLI).

### When Planning Changes

| Change type                    | Reference                                                                                  |
| ------------------------------ | ------------------------------------------------------------------------------------------ |
| New module / refactor          | `architecture.md` + `source-tree-analysis.md`                                              |
| New package                    | `development-guide.md` → "Add a system-wide package" / "Add a user-only package"           |
| Hyprland keybind / window rule | `.config/hypr/hyprland.conf`, `.config/hypr/windowrules.conf`; reload via `hyprctl reload` |
| Service with runtime state     | `architecture.md` § Impermanence + `modules/core/impermanence.nix`                         |
| Secret addition                | `development-guide.md` → "Add a secret"; `modules/core/secrets.nix`                        |
| Hardware / NVIDIA tweak        | `modules/core/graphics.nix`, `modules/core/boot.nix`                                       |
| Fresh install                  | `deployment-guide.md` + `install/INSTALL.md`                                               |

### Hard Constraints (Non-Negotiables)

The full list is in `../AGENTS.md`. Summary:

1. Declarative supremacy — every change is a Nix expression.
2. Language purity — non-Nix code in XDG-mirrored dirs, referenced via `builtins.readFile`.
3. No comments — anywhere.
4. Zero plain-text secrets — sops-nix + age only.
5. Impermanence — only `/nix`, `/persistent`, `/home/m` survive.
6. NVIDIA + Wayland only — no X11 fallback.
7. Out of the box — every program works on first launch.
8. No FDE — main drive intentionally unencrypted.

---

_Documentation generated by BMAD Method `document-project` workflow._
