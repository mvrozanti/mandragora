# Claude Code — Mandragora (Repo-Level)

**Read `AGENTS.md` first.** It contains all universal rules, non-negotiables, and system context. This file adds Claude Code-specific context for work within this repo.

---

## Claude-Specific Workflow

Claude Code may run `sudo nixos-rebuild switch --flake <worktree>#mandragora-desktop` directly to iterate before landing, but only from a clean commit (a WIP commit in the worktree is fine) that descends from what is running: the `nixos-rebuild` on PATH is a guard that refuses anything else (see `docs/worktrees.md`, "Activation only moves forward"). Use `mandragora-switch` for the full commit+build+push cycle. Claude does not need the approval of the user to run switch.

---

## Multi-Agent File Safety Rule

**Never rewrite a file from scratch.** Other agents may have edited the same file earlier in the session or in a prior session. Always read the current on-disk state before making any change. Use targeted edits — patch only the blocks relevant to your task.

---

