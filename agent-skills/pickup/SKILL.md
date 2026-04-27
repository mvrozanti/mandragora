---
name: pickup
description: Use when the user wants to resume work from a handoff written by another agent. Reads the latest open handoff addressed to Claude from ~/.ai-shared/handoffs/ and continues from there. Triggered explicitly via /pickup.
---

# pickup — Resume From Another Agent's Handoff

## Overview

`/pickup` is the read side of the cross-agent handoff protocol (write side: `/handoff`). It scans `~/.ai-shared/handoffs/` for open handoffs addressed to Claude, surfaces them, then loads the chosen one as conversation context and marks it consumed.

The full protocol — file naming, frontmatter schema, status lifecycle — lives in `~/.ai-shared/AGENTS.md` under "Cross-Agent Handoff Protocol".

## When to Use

- User says "pickup", "/pickup", "resume from gemini", "what did the other agent leave for me".
- Start of a session where the user wants to continue work another agent began.

**Do NOT use when:**
- User asks an unrelated question — handoffs are baton-passes, not background reading.
- No handoffs directory exists or it's empty — just say so.

## Workflow

```
1. List        ls ~/.ai-shared/handoffs/*.md 2>/dev/null
               Filter: frontmatter `to: claude*` AND `status: open`
               Sort: newest first by filename (timestamps sort lexically)
2. Choose      - 0 matches → tell the user, stop.
               - 1 match  → read it, show summary, ask "pick this up?"
               - N>1      → list them (timestamp, from, task one-liner),
                            ask which to pick up.
3. Verify      Before acting on the handoff:
                 - Confirm "Files touched" still exist on disk.
                 - Re-run `git status` if a project path is given —
                   compare to "Rebuild status".
                 - Re-run `git -C /etc/nixos/mandragora worktree list` to check for open worktrees.
                 If state diverges materially, surface the divergence
                 to the user before continuing.
4. Mark        Edit the handoff frontmatter:
                 status: consumed
                 consumed_at: <UTC ISO timestamp>
               Keep the file in place — append-only history.
5. Continue    Resume from "Next step", asking the user any "Open
               questions" before acting on them.
```

## Listing & Filtering

Open handoffs addressed to Claude:

```bash
for f in ~/.ai-shared/handoffs/*.md; do
  [ -f "$f" ] || continue
  awk '/^---$/{n++; next} n==1' "$f" | grep -q '^to: claude' || continue
  awk '/^---$/{n++; next} n==1' "$f" | grep -q '^status: open' || continue
  echo "$f"
done | sort -r
```

Newest first because timestamps in filenames are `YYYYMMDDTHHMMSSZ` (UTC, no separators) — they sort lexically.

## Marking Consumed

Use the Edit tool to flip two frontmatter lines:

```
status: open       → status: consumed
consumed_at:       → consumed_at: 2026-04-26T15:08:00Z
```

Compute the timestamp with `date -u +%Y-%m-%dT%H:%M:%SZ`. Don't rewrite the rest of the file.

## Critical Rules

1. **Verify before acting.** A handoff is a snapshot from minutes-to-days ago. Re-check the on-disk state — files may have moved, locks may have expired, the rebuild may have happened. If state has drifted, name the drift to the user before continuing.
2. **Mark consumed immediately after read.** Otherwise a parallel session can pick the same handoff up and double-execute the work.
3. **Don't delete.** Keep consumed handoffs as audit trail. Cleanup is a separate, manual decision.
4. **Treat "Next step" as a starting point, not a command.** If the handoff says "run mandragora-switch" but the working tree is now clean, the right action might be no-op + verify.
5. **Surface "Open questions" up front.** Don't silently assume answers; ask the user before proceeding past them.

## Hand-Off

After successful pickup, report to the user:

```
Picked up: <filename>
  from: <agent>
  task: <one-line summary>
  next step: <one-line>
Marked consumed at <timestamp>.
[Then proceed with the next step or surface any divergence/open questions.]
```

If nothing to pick up:

```
No open handoffs addressed to claude in ~/.ai-shared/handoffs/.
```

Then stop or proceed per user direction.
