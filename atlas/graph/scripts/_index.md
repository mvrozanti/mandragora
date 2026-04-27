---
type: index
tags: [atlas, index, scripts]
---

# Scripts

Wired-in entries from `.local/bin/`. Each is wrapped by a module via `pkgs.writeShellScriptBin` + `builtins.readFile` ([[../concepts/language-purity|Language Purity]]). Only scripts referenced by a module or central to workflow get a node here — the long tail of utilities lives on disk only.

Up: [[../_MOC|Atlas MOC]] · See: [[../modules/_index|Modules]]

## System workflow

- [[mandragora-switch]] — rebuild + commit + push (the master ritual)
- [[mandragora-commit-push]] — docs-only commit (no rebuild)
- [[mandragora-diff]] — staged-diff preview
- [[health-check]] — audit script
- [[strays]] — find orphaned/uncommitted files

## AI / LLM

- [[gemma]] — wrapped by [[../modules/core/ai-local]]
- [[local-ai-mcp-server]] — MCP server for Crush TUI

## Secrets / network

- [[oracle-hosts-inject]] — pulls oracle IP from sops, edits `/etc/hosts`

## Desktop / lighting

- [[keyleds-workspace-watcher]] — RGB workspace reactor
- [[keyledsd-reload]] — reload keyledsd config
- [[gap-adjust]] — Hyprland gap tweaker
- [[blur-adjust]] — Hyprland blur tweaker
- [[opacity-adjust]] — Hyprland opacity tweaker

## Audio / input

- [[cycle-audio-output]] — toggle Pipewire sinks

## Mail / sync

- [[mbsync-hotmail-sync]] — Hotmail IMAP sync
- [[imap-notify]] — IMAP IDLE notifier

## Capture

- [[capture]] — screen capture
- [[screenshot-window]] — window screenshot
