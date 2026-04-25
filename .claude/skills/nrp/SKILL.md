---
name: nrp
description: Use when /etc/nixos/mandragora has uncommitted changes that span multiple unrelated topics and the user wants each topic committed separately. Walks the diff, groups hunks by concern, and commits each group as its own commit.
---

# nrp — Split & Commit Mandragora Diff By Topic

## Overview

`/etc/nixos/mandragora` accumulates parallel changes from many sessions and agents. A single `mandragora-switch` would lump them into one mixed commit. This skill breaks that diff into topical commits before any rebuild.

**Core principle:** one concern per commit. Never mix unrelated hunks even when they live in the same file.

## When to Use

- User says "commit the diff", "split these changes", "commit each", "commit by topic" inside the mandragora repo.
- `git status` shows multiple modified files OR a single file with hunks for unrelated concerns.
- Before running `mandragora-switch` when changes are non-atomic.

**Do NOT use when:**
- Working tree is clean.
- All changes are clearly one topic — just use `mandragora-switch <msg>`.
- User asked for `mandragora-switch` directly — respect their explicit command.

## Workflow

```
1. Survey       git -C /etc/nixos/mandragora status --short
                git -C /etc/nixos/mandragora diff
                                (read every hunk; do not skim)
2. Group        Bucket files/hunks by topic. Name each bucket.
3. Plan         Show the user the bucket list (labels + files/hunks per bucket).
                Messages are NOT shown yet — they're generated per bucket in
                step 4. Wait for approval of the grouping only.
4. Commit loop  For each bucket:
                  a. git add <files>           (whole-file groups)
                     OR git add -p             (hunk-level groups)
                  b. git diff --cached --stat  (verify scope)
                  c. resolve message:
                       - if user supplied messages via args, take the next one
                         (see "Commit Message Source" for the splitting rule)
                       - else: pipe cached diff to `claude -p --model haiku
                         --bare` (see "Commit Message Source")
                  d. show message to user, wait for ack (or edit)
                  e. git commit -m "<msg>"
5. Verify       git status (must be clean OR contain only un-bucketed leftovers)
                git log --oneline -<N>         (<N> = number of buckets)
6. Hand off     Tell user: commits made, whether to run mandragora-switch
                (rebuild) next. Do NOT auto-rebuild.
```

## Grouping Heuristics

Group hunks together when they share any of:

- **Same module purpose** — e.g. all waybar styling, all hyprland keybinds, all lf config.
- **Same fix/feature** — a keymap added in `nvim/map.vim` plus a snippet it depends on.
- **Same external trigger** — bumping a pinned commit and adjusting the patch it required.

Split apart when:

- Different program (nvim vs waybar) — almost always separate.
- Different layer (system module vs user dotfile) — separate.
- Cosmetic vs behavioral change in same file — separate hunks via `git add -p`.
- Unrelated typo/comment cleanup — its own "chore:" commit.

## Commit Message Source

The skill is invoked with optional positional args (`$*`). Two paths:

### Args provided

The args string is split on `;;` (double semicolon) — chosen because it's
unlikely to appear inside a real subject. Trim whitespace on each part. Pair
the resulting messages with buckets in order.

- `count(messages) == count(buckets)` → straight pairing.
- `count(messages) == 1` → ask: reuse for all, or only bucket 1 and generate
  the rest?
- Any other mismatch → stop and ask. Don't guess.

### No args — generate via Haiku

For each bucket, after staging it, pipe recent log + staged diff to Claude
Haiku in headless mode. The log is always included so Haiku can mirror style:

```bash
cd /etc/nixos/mandragora
RECENT=$(git log --oneline -20)
DIFF=$(git diff --cached)
printf '## RECENT LOG (style reference)\n%s\n\n## STAGED DIFF\n%s\n' \
  "$RECENT" "$DIFF" | \
  claude -p --model claude-haiku-4-5 --bare \
    --append-system-prompt "$(cat <<'EOF'
You write a single git commit subject for a personal NixOS+Hyprland dotfiles
repo. The user message contains the recent commit log (for style) followed by
the staged diff. Mirror the log's style exactly: if the log uses Conventional
Commits prefixes, use one; if it doesn't, don't invent one. Output exactly
ONE line, ≤72 chars, imperative mood, no trailing period, no quotes, no
backticks, no markdown fences, no preamble, no body. Nothing else — the raw
subject text only, no surrounding punctuation of any kind.
EOF
)" \
    "Write the commit subject for the staged diff."
```

Notes:
- `--bare` strips hooks, MCP, plugins, CLAUDE.md auto-discovery — fast and
  deterministic. Required for tool-driven generation.
- `-p` is print-and-exit; stdout is the raw subject.
- Capture stdout, strip trailing newline, **show to user and wait for ack
  or edit** before `git commit -m "<msg>"`. On reject, let the user supply
  one or regenerate with their feedback appended to the prompt.
- **Sanitize before showing**: Haiku sometimes wraps the subject in backticks
  or stray quotes despite the prompt. Strip leading/trailing `` ` ``, `'`,
  `"` characters and any leading/trailing whitespace before display. If the
  output still contains commentary or multiple lines, take only the first
  line — and if that line still looks decorative, write your own subject
  rather than commit the noise.

### Style rules (both paths)

- ≤72 char subject, imperative, no trailing period.
- Body only if *why* isn't obvious from the diff.
- **No `Co-Authored-By` trailer** unless the user asks — this is the user's
  personal config.

## Hunk-Level Staging

When two topics live in the same file, use interactive staging:

```
git -C /etc/nixos/mandragora add -p path/to/file
```

In the prompt: `y` stage, `n` skip, `s` split further, `e` edit hunk manually, `q` abort. After staging the first topic's hunks, commit, then loop back for the next topic.

If `-p` splitting becomes hairy, fall back to:
1. `git stash` the whole file
2. `git stash show -p | head -<lines>` to inspect
3. Manually re-apply only the hunks you want, commit, then `git stash pop` the rest

## Quick Reference

| Situation | Command |
|---|---|
| Survey diff | `git -C /etc/nixos/mandragora status --short && git -C /etc/nixos/mandragora diff` |
| Stage whole file | `git add <file>` |
| Stage hunks | `git add -p <file>` |
| Verify scope before commit | `git diff --cached --stat` |
| Generate message (no args) | see "Commit Message Source" — Haiku call |
| Commit | `git commit -m "<msg>"` (after user acks the message) |
| Inspect last N commits | `git log --oneline -<N>` (e.g. `-5`) |
| Undo last commit (keep changes) | `git reset --soft HEAD~1` |

All run with `-C /etc/nixos/mandragora` or `cd` into the repo once.

## Critical Rules

1. **Never `git add -A`.** It drags in unrelated changes from parallel agent sessions. Always name files or use `-p`.
2. **Never amend.** Each topic gets a NEW commit. If a commit is wrong, `git reset --soft HEAD~1` and redo.
3. **Never push.** This skill only commits locally. Pushing is the user's call.
4. **Never run `nixos-rebuild` or `mandragora-switch` from this skill.** Rebuild is a separate step the user invokes after reviewing the commit list.
5. **Confirm groupings before committing** when more than 2 buckets or any hunk-level split is involved. The cost of a wrong split is high; one extra question is cheap.
6. **Read the file, don't trust the diff label.** A change in `home.nix` could be three unrelated topics. Open the file at the hunk to know.
7. **Respect Multi-Agent File Safety.** Other agents may have edited concurrently — the diff on disk is ground truth, not your mental model from earlier in the session.

## Common Mistakes

| Mistake | Fix |
|---|---|
| `git add -A` "to keep it simple" | Name files explicitly. The whole point is selective staging. |
| Committing without showing the user the bucket plan | Stop. Print buckets + messages. Wait for ack. |
| Using `mandragora-switch` mid-flow | That tool is one-shot add-all-and-commit; it defeats this skill. Use plain `git commit`. |
| Inventing commit-message conventions | Match `git log --oneline -20` style exactly. |
| Treating a single modified file as one topic | Open it. Two unrelated hunks = two commits. |
| Forgetting leftovers | After loop, `git status` must be intentional — clean, or only what user explicitly deferred. |

## Hand-Off

After the last commit, report to the user:

```
Committed N topics:
  <sha>  <subject>
  <sha>  <subject>
  ...
Working tree: <clean | files still pending: ...>
Next step: run `mandragora-switch` to rebuild, or `git push` to publish.
```

Then stop. Do not rebuild or push unprompted.
