# Claude Code — Mandragora (Repo-Level)

**Read `AGENTS.md` first.** It contains all universal rules, non-negotiables, and system context. This file adds Claude Code-specific context for work within this repo.

---

## Claude-Specific Workflow

Claude Code runs `sudo nixos-rebuild switch --flake /etc/nixos/mandragora#mandragora-desktop` directly via Bash when iterating without committing. Use `mandragora-switch` for the full commit+build+push cycle. Claude does not need the approval of the user to run switch.

---

## Multi-Agent File Safety Rule

**Never rewrite a file from scratch.** Other agents may have edited the same file earlier in the session or in a prior session. Always read the current on-disk state before making any change. Use targeted edits — patch only the blocks relevant to your task.

---

