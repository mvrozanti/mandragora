# Worktree by Default — Every Git Repo

Applies to every agent (Claude, Gemini, Qwen, crush, subagents) editing
any file tracked by any git repository on this machine — not just
`/etc/nixos/mandragora`. Mandragora-specific additions (mid-switch
guard, `mandragora-switch` worktree mode) live in the repo's
`docs/worktrees.md`.

## Why

Several agents routinely work at once, often in the same repo. A shared
checkout has one index and one working tree, so any agent's `git add`,
`git stash`, `git checkout`, formatter run, or half-finished edit
reaches everyone else's work. A worktree gives each task its own tree
and index; nothing another agent does there can touch it. The cost is
two git commands and a directory. There is no carve-out for "small"
edits: the risk is someone *else* acting mid-edit, which size does not
change.

Only exceptions: files outside any git repo, and a repo with no commit
yet (nothing to branch from — make the first commit, then worktree).

## Coordination protocol

Coordination is the point. Worktrees only help if every agent can see
what the others are doing.

### 1. Look before you start

```bash
git -C <repo> worktree list
git -C <repo> status --short
```

`git worktree list` is the registry of in-flight work. A worktree whose
branch name matches your task means someone is already on it — surface
that to the user instead of starting a parallel copy. A dirty main tree
is someone else's WIP: leave it alone.

### 2. One worktree per task, named after the task

```bash
repo=$(git rev-parse --show-toplevel)
name=<short-task-slug>
wt="$HOME/.local/share/worktrees/$(basename "$repo")/$name"
git -C "$repo" worktree add -b "agent/$name" "$wt" HEAD
```

Claude Code's native `EnterWorktree` (`<repo>/.claude/worktrees/…`) and a
repo's own convention (mandragora: `.worktrees/`) are equally fine —
`git worktree list` finds them all. Use a descriptive slug, not a bare
timestamp: the name is how the next agent knows what you are doing.

### 3. Stay inside your own worktree

- Never edit, commit in, rebase, or remove another agent's worktree or
  branch. A stale-looking worktree is unfinished work until the user
  says otherwise.
- Never `git stash` bare — the stash stack is shared across every
  worktree. Use a WIP commit instead.
- Stage by path, never `git add -A` (AGENTS.md Rule 21). Do not create
  convenience symlinks into a worktree at a path an ignore rule
  covers — that is exactly how the 2026-09-27 checkpoint loss happened.

### 4. Land it and clean up

```bash
git -C "$repo" merge --ff-only "agent/$name"
git -C "$repo" worktree remove "$wt"
git -C "$repo" branch -d "agent/$name"
```

If the fast-forward fails, master moved: rebase your branch onto it in
your worktree, then retry. Never merge into a main tree that has
uncommitted changes you did not author — stop and report. Read what the
merge prints; `git show --stat HEAD` must match what you edited.

If you have to stop before landing, leave the worktree in place and
say so (path + branch) in your final message or handoff, so the next
agent can pick it up rather than redo it.

Merging and removing your own worktree are part of finishing the task.
Pushing still follows each repo's normal commit/push authorization.
