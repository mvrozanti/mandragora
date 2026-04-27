# Documentation Index

Single LLM router. Every survivor doc is one hop from here.

## Always load first

- [`../AGENTS.md`](../AGENTS.md) — non-negotiables, file safety, per-agent
  policy variances, edit→rebuild→verify→commit summary.
- Agent-specific delta: [`../CLAUDE.md`](../CLAUDE.md) (Claude Code),
  [`../GEMINI.md`](../GEMINI.md) (Gemini CLI),
  [`../local-llm.md`](../local-llm.md) (Telegram-bridged local model).

## Topical (lazy-load)

| Topic | File |
|-------|------|
| Architecture (composition, modules, theming, boot, audits) | [`architecture.md`](architecture.md) |
| Hardware (build, peripheral control, NVIDIA tuning) | [`hardware.md`](hardware.md) |
| Edit → rebuild → verify → commit (full common-tasks reference) | [`workflow.md`](workflow.md) |
| What survives reboot (impermanence + user-data ranking) | [`persistence.md`](persistence.md) |
| Secrets contract (sops-nix, age, agent rules) | [`secrets.md`](secrets.md) |
| Worktree isolation + mid-switch guard (Rule 10 detail) | [`worktrees.md`](worktrees.md) |
| Routing through `rtk` (Rule 13 detail, full subcommand list) | [`rtk.md`](rtk.md) |
| Cross-agent handoff protocol (`/handoff`, `/pickup`) | [`handoff.md`](handoff.md) |

## Reference

- [`../DECISIONS.md`](../DECISIONS.md) — every resolved technical choice
  (identity, boot, disk, display, hardware, secrets, external systems).
- [`../install/INSTALL.md`](../install/INSTALL.md) — fresh-install runbook
  (partition → mount → bootstrap age key → install → reboot).

## Where things live

- Module configs: `modules/{core,desktop,user,audits}/<thing>.nix`.
- Non-Nix code (config files, scripts, css, lua): XDG-mirrored at repo
  root — `.config/<app>/`, `.local/bin/`, `snippets/`.
- Custom packages: `pkgs/<name>/default.nix` registered in
  `pkgs/overlays.nix`.
- Encrypted secrets vault: `secrets/secrets.yaml` (sops-encrypted; never
  open directly — use `sops`).

## Self-contained subprojects

- [`../appendix/wsl/README.md`](../appendix/wsl/README.md) — Mandragora
  profile under WSL2 (corporate-laptop fallback).
- [`../appendix/ventoy-usb/README.md`](../appendix/ventoy-usb/README.md) —
  multiboot rescue/install USB.
