# Worktree Isolation + Mid-Switch Guard

This is the full body of AGENTS.md Rule 10. Load it when you need to start
a parallel-safe edit session, after a `pgrep` hit, or when something seems
off with `git worktree list`.

## Before touching any file under `/etc/nixos/mandragora/`

### 1. Check for an active switch

If `nixos-rebuild switch` or `mandragora-switch` is running, stop and
surface to the user before proceeding:

```bash
pgrep -a -f "nixos-rebuild switch" 2>/dev/null
pgrep -a -f "mandragora-switch" 2>/dev/null
```

If either returns a PID, do not start edits.

### 2. Use a git worktree for parallel work

When another agent session may be editing the repo concurrently, create
an isolated branch instead of editing the main tree directly:

```bash
wt=/home/m/.local/share/mandragora-worktrees/agent-$(date -u +%s)
git -C /etc/nixos/mandragora worktree add -b agent/$(date -u +%s) "$wt" HEAD
```

Edit inside `$wt`. After syntax-check (Rule 11), merge back and clean up:

```bash
git -C /etc/nixos/mandragora merge --ff-only agent/<branch>
git -C /etc/nixos/mandragora worktree remove "$wt"
git -C /etc/nixos/mandragora branch -d agent/<branch>
```

For single-agent work with no parallel session active, editing
`/etc/nixos/mandragora/` directly is fine — no worktree needed.

`git -C /etc/nixos/mandragora worktree list` shows all open worktrees.
Stale worktrees from prior sessions indicate unfinished work — surface
to the user before proceeding.
