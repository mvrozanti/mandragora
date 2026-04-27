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

## Script-side enforcement

`mandragora-switch` adds two guards independent of the agent contract:

1. **flock on `$XDG_RUNTIME_DIR/mandragora-switch.lock`** — held across
   the entire `add → commit → push` cycle. A second invocation aborts
   immediately with the holder's PID. Prevents two switches from
   racing into `git add -A`.

2. **Working-tree stability window** — before staging, snapshots
   `git status --porcelain` and the mtimes of every dirty/untracked
   file, sleeps `MANDRAGORA_SWITCH_STABILITY_SECONDS` (default 2s),
   re-snapshots, and aborts if anything changed. Catches another
   editor that is actively writing files in the main tree. Quiet
   trees pass instantly. Override with `--force` or
   `MANDRAGORA_SWITCH_FORCE=1`. Set the env var to `0` seconds to
   disable the check entirely.

Together with the `pgrep` agent-side check, these mean an
editor-vs-switch race surfaces as an explicit abort with a diff,
not as a silent sweep of someone else's WIP into your commit.
