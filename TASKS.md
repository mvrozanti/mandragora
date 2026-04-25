# Unified AI Task Bridge

This file persists tasks, states, and workflows across different AI agents (Claude, Gemini, etc.).

## Active Tasks
- Clean up partial Ollama model blobs in `/var/lib/private/ollama/models/blobs/` to reclaim space from cancelled downloads.
- Phase 7: Audit and Nixify scripts from `~/projects/mandragora/.local/bin/` (unclaimed)
- Phase 6: Seafile client config (unclaimed)
- Phase 5: Shadow profile LUKS2 setup (deferred — dedicated session required)

## Completed Tasks
- [2026-04-21] Create `nixos-clean` command to prune generations and optimize store (Gemini)
- [2026-04-19] Set up initial NixOS Hyprland config (Claude)
- [2026-04-19] Investigate Gemma crash (Gemini)
- [2026-04-19] Upgrade local MCP server to support multiple models (Gemma 3 + DeepSeek R1 70B)
- [2026-04-19] Pull DeepSeek R1 70B Abliterated (Gemini)
- [2026-04-19] Configure MCP integration for local Ollama instance (Claude/Gemini)
- [2026-04-20] Add super+E / super+shift+E / super+ctrl+E hyprland keybinds (dwindle rotate equiv) (Claude)
- [2026-04-20] Install gemini-cli to home.packages (Claude)
- [2026-04-20] Fix Tridactyl native messenger registration via programs.firefox.nativeMessagingHosts (Claude)
- [2026-04-20] Deploy unugly.css theme to ~/.config/tridactyl/themes/ — fixes dark gray hint colors (Claude)
- [2026-04-20] Restructure repo: killed snippets/, all files moved to XDG-mirrored dirs (.config/, .local/bin/, etc/) (Claude)
- [2026-04-20] Phase 6: earlyoom enabled (services.earlyoom, 5%/10% thresholds) — done by another agent

## Retrospectives & Lessons Learned
- **Config Distribution (2026-04-19):** Gemini incorrectly *moved* `GEMINI.md` out of the version-controlled `/etc/nixos/mandragora` repo and replaced it with a symlink to `~/.ai-shared`. **Lesson:** AIs must **COPY** configuration files from version-controlled repositories into the `~/.ai-shared` bridge, never *move* them and replace them with symlinks, to preserve Git tracking.
- **Full-File Rewrite Clobber (2026-04-20):** An agent rewrote `modules/user/home.nix` from scratch, dropping `programs.firefox` (with `nativeMessagingHosts`) that a prior agent had added in the same session. Firefox became uninstalled. **Lesson:** NEVER rewrite a file from scratch without reading its current on-disk state first. Always use targeted edits (append, patch specific blocks). If a full rewrite is truly necessary, read the file, diff mentally against your intent, and preserve every section you are not explicitly replacing.

---
*Append new tasks or state updates below.*
- [2026-04-22] Change Hyprland resize binding to Alt+RMB (Gemini)
- [2026-04-25] Unified memory store: moved Claude's per-agent memory dir into `~/.ai-shared/memory/`; symlinked Claude harness path back. AGENTS.md / repo-level CLAUDE.md / repo-level GEMINI.md updated so both agents start with the same accumulated knowledge. Gemini now MUST read `~/.ai-shared/memory/MEMORY.md` at session start (no auto-injection). (Claude)

## Active: mandragora-usb + refiner (2026-04-25, Claude)

Brainstorming + spec + plan complete. Implementation NOT yet started.

**Spec:** `/etc/nixos/mandragora/docs/superpowers/specs/2026-04-25-mandragora-usb-refiner-design.md` (commit `a7e8d1eb`)
**Plan:** `/etc/nixos/mandragora/docs/superpowers/plans/2026-04-25-mandragora-usb-refiner.md` (commit `475b82da`)

**Last left off:** about to start M1.1 (add `nixos-generators` flake input). User had to reboot.

**Decisions beyond the spec/plan (not in either file):**
- Stay on `master`, no feature branch.
- Hybrid execution: mechanical tasks inline (~30), substantive via subagent (~15), risky desktop-module refactors via subagent + 2 reviewers (~5). The full subagent-driven mode (150 dispatches) is overkill for the many tiny tasks in this plan.
- The plan's scripts and Nix derivations have explanatory comments for plan readers; CLAUDE.md Rule #3 (no comments in code) applies when implementing — strip them at commit time.
- Apply Rule #11 after each `.nix` edit (`nix-instantiate --parse <file>`).
- M1.7 (real-USB flash + boot one machine) is no longer a hard exit gate; do it when convenient before v1 declared done. VM-driven work (M2 onward) proceeds independently.
- M3.7 (manual end-to-end install in refiner) and M9 `--auto` test require human in the loop for first runs.
- Lock-protocol identity verification flaw discussed (`agent: claude-opus-4-7` is a model ID, not a per-instance ID; `pid` not accessible from agent). Refactor deferred. Filed as future work; current rule remains a coarse "someone is working" signal.

**Next concrete action when resuming:** start M1.1. Read the plan's M1.1 section, add `nixos-generators` to `flake.nix` inputs and outputs signature, run `nix flake check --no-build`, commit. Then M1.2.
