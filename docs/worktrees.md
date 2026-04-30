# Worktree by Default + Mid-Switch Guard

This is the full body of AGENTS.md Rule 10. Load it before any edit
under `/etc/nixos/mandragora/`, after a `pgrep` hit, or when something
seems off with `git worktree list`.

## The default is a worktree

Create a worktree first. Edit there. Merge back when done. Treat the
main tree as a publish target, not a scratchpad.

The narrow carve-out for direct-tree edits: a **single-file change you
can stage and commit in under ~30 seconds**, where you control the
entire edit→stage→commit window. Anything multi-file, anything that
introduces an untracked file, anything you might leave half-finished
while you go read another file — worktree.

When in doubt, worktree. The cost is two git commands and a directory.
The cost of getting it wrong is rewriting history (or, worse, not
noticing).

## Why `pgrep` alone is not enough

`pgrep -a -f "nixos-rebuild switch"` and `pgrep -a -f "mandragora-switch"`
detect a rebuild that is **already running**. They do not detect:

- another agent that is currently editing files,
- another agent that has staged changes but not yet committed,
- another agent between `git add -A` and `git commit`,
- another agent about to invoke `mandragora-switch` in the next second.

A clean `pgrep` therefore does not prove you are alone. It is a
**necessary** check (always run it; if it hits, stop and surface to
the user), but it is **not sufficient** to unlock direct-tree editing.

## The failure mode this rule exists to prevent

Documented in memory: `feedback_parallel_commit_staging_leak.md`.

Two agents work in the same tree. Agent A writes `new-file.nix`.
Agent B's `mandragora-switch` runs `git add -A` and sweeps
`new-file.nix` into Agent B's commit, even though Agent B never
touched it. The build still succeeds and the file ends up tracked,
but it lands under Agent B's commit message — orphaned from its
intent. History becomes misleading; reverting the wrong commit
removes unrelated work.

The script-side guards in `mandragora-switch` (flock + stability
window) prevent two **switches** from racing each other. They do
**not** prevent this index leak, because the leak happens in the
single switch that wins the flock. Worktree isolation is the only
mechanism that closes this gap from the agent side.

## Procedure

### 1. Pre-edit check (always)

```bash
pgrep -a -f "nixos-rebuild switch" 2>/dev/null
pgrep -a -f "mandragora-switch"   2>/dev/null
```

If either returns a PID (other than your own shell), stop and surface
to the user before proceeding.

### 2. Create the worktree

```bash
ts=$(date -u +%s)
wt=/home/m/.local/share/mandragora-worktrees/agent-$ts
git -C /etc/nixos/mandragora worktree add -b agent/$ts "$wt" HEAD
```

Edit inside `$wt`. Run syntax-check (Rule 11) there. The main tree
is unaffected; another agent's `git add -A` cannot reach your files.

### 3. Merge back and clean up

```bash
git -C /etc/nixos/mandragora merge --ff-only agent/<branch>
git -C /etc/nixos/mandragora worktree remove "$wt"
git -C /etc/nixos/mandragora branch -d agent/<branch>
```

Then run `mandragora-switch` from the main tree. Any parallel
agent will be merging from their own worktree on the same schedule;
the flock serializes the switches.

### 4. Audit

```bash
git -C /etc/nixos/mandragora worktree list
```

Stale worktrees from prior sessions indicate unfinished work —
surface to the user before reusing or deleting.

## Script-side enforcement (defense in depth)

`mandragora-switch` adds two guards independent of the agent contract:

1. **flock on `$XDG_RUNTIME_DIR/mandragora-switch.lock`** — held
   across the entire `add → commit → push` cycle. A second invocation
   aborts immediately with the holder's PID. Prevents two switches
   from racing into `git add -A`.

2. **Working-tree stability window** — before staging, snapshots
   `git status --porcelain` and the mtimes of every dirty/untracked
   file, sleeps `MANDRAGORA_SWITCH_STABILITY_SECONDS` (default 2s),
   re-snapshots, and aborts if anything changed. Catches another
   editor that is actively writing files in the main tree. Quiet
   trees pass instantly. Override with `--force` or
   `MANDRAGORA_SWITCH_FORCE=1`. Set the env var to `0` seconds to
   disable the check entirely.

These are last-line defenses. They catch *some* races and surface
them as explicit aborts with diffs. They do **not** replace the
worktree default — the staging-leak failure mode above happens
inside the single switch that wins the flock, where neither guard
fires. Use a worktree.
