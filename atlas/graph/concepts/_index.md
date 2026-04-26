---
type: index
tags: [atlas, index, concepts]
---

# Concepts

Cross-cutting hubs. Each concept is touched by many modules — they're the bright stars in the graph view.

Up: [[../_MOC|Atlas MOC]]

## Hardware & display

- [[nvidia]] — RTX 5070 Ti, beta drivers, VRAM gating
- [[wayland]] — Hyprland, no X11

## Storage & state

- [[impermanence]] — root wipe, `/persistent`, bind-mounts

## Identity & secrets

- [[secrets-sops]] — sops-nix, age, oracle-hosts injection

## AI

- [[ai-stack]] — Ollama, gemma.py, MCP server, Skill ecosystem ties

## Audio

- [[audio-pipeline]] — Pipewire → Wireplumber → mpd → waybar

## User-space patterns

- [[zx-dirs]] — single-source-of-truth directory shortcuts (zsh + lf)
- [[skill-ecosystem]] — BMAD skills via flake inputs

## Workflow & invariants

- [[agent-locks]] — `mandragora-lock` multi-agent safety
- [[declarative-supremacy]] — every change is Nix
- [[language-purity]] — XDG-mirrored non-Nix files via `readFile`
- [[rebuild-workflow]] — `mandragora-switch` flow
