---
type: concept
tags: [concept, agents, workflow]
---

# Agent worktrees

Git worktrees are the coordination protocol when multiple AI agents (or humans) edit the repo at once.

**Before any edit:** check for a running `nixos-rebuild switch` or `mandragora-switch` process via `pgrep`. If found, surface to the user and wait.

**For parallel sessions:** each agent creates a throwaway branch in `/home/m/.local/share/mandragora-worktrees/` via `git worktree add -b agent/<id>`, edits there, then fast-forward merges back to main before running `mandragora-switch`. Open worktrees are visible to all via `git worktree list`.

**For single-agent work:** editing the main tree directly is fine when no parallel session is active.

## Touched by

- [[../scripts/mandragora-switch]] — guarded by pgrep at startup
- [[../modules/user/home]] — wraps mandragora-switch as a binary

See: [[../../non-negotiables]]
