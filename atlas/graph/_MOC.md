---
type: moc
tags: [atlas, moc]
---

# Mandragora Atlas — Map of Content

A constellation of small interlinked nodes covering every meaningful piece of `/etc/nixos/mandragora`. Open `Graph view` in Obsidian to see the wiring at a glance.

Each node is small on purpose. **Connectedness over content.**

## Buckets

- [[modules/_index|Modules]] — every `.nix` under `modules/{core,desktop,user,audits}`
- [[configs/_index|Configs]] — every `.config/<app>/` directory
- [[scripts/_index|Scripts]] — the wired-in scripts from `.local/bin/`
- [[packages/_index|Packages]] — custom packages under `pkgs/`
- [[concepts/_index|Concepts]] — cross-cutting hubs that pull the graph together

## Concept hubs

The brightest stars. Most leaves link out to one or more of these.

- [[concepts/nvidia|NVIDIA]] — RTX 5070 Ti, beta drivers, VRAM gating
- [[concepts/wayland|Wayland]] — Hyprland, no X11
- [[concepts/impermanence|Impermanence]] — root wipe, `/persistent`
- [[concepts/secrets-sops|Secrets (sops-nix)]]
- [[concepts/ai-stack|Local AI stack]]
- [[concepts/audio-pipeline|Audio pipeline]]
- [[concepts/zx-dirs|zX directory shortcuts]]
- [[concepts/agent-locks|Agent locks]]
- [[concepts/declarative-supremacy|Declarative supremacy]]
- [[concepts/language-purity|Language purity]]
- [[concepts/skill-ecosystem|Skill ecosystem]]
- [[concepts/rebuild-workflow|Rebuild workflow]]

## Existing prose docs (siblings to this graph)

- [[../README|atlas README]]
- [[../architecture]]
- [[../hardware]]
- [[../software]]
- [[../non-negotiables]]

## Reading the graph

- **Tags drive color groups.** Set color groups in Obsidian for `#nvidia`, `#wayland`, `#audio`, `#ai`, `#secrets`, `#impermanence`, etc.
- **Edge density signals coupling.** Modules with many edges (e.g. [[modules/desktop/hyprland]], [[modules/user/home]]) are the load-bearing pieces.
- **Hubs orbit at the center.** Concept docs accumulate backlinks; layer indexes are the rings.
