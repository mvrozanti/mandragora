# Cross-Agent Handoff Protocol

A handoff is an explicit, user-initiated baton-pass from one agent to
another (e.g. Claude → Gemini). It carries enough context that the
receiving agent can continue mid-thought without forcing the user to
re-explain.

**Triggering is always explicit.** Agents do not write handoffs on every
turn — only when the user invokes `/handoff` (write side) or `/pickup`
(read side). Auto-handoff is out of scope.

## File layout

```
~/.ai-shared/handoffs/<ISO-timestamp>-<from>-to-<to>.md
```

- `<ISO-timestamp>` is `YYYYMMDDTHHMMSSZ` (UTC, no separators) — sorts lexically.
- `<from>` and `<to>` are short agent IDs: `claude`, `gemini`, `qwen`, etc.
- Files are append-only history; never deleted. Status flips to `consumed`
  after pickup. Terminal-status files (consumed/complete/closed/abandoned)
  older than 7 days are MOVED to `handoffs/archive/` by
  `~/Projects/orderbook-algotrading/scripts/handoff_gc.py` — history
  preserved, hot directory kept small. Open handoffs are never moved.
- Optional frontmatter field `next_iter_class: mechanical|reasoning`
  (orderbook-algotrading autopilot only): declares the difficulty of the
  recommended next step; the loop downshifts `mechanical` iters
  opus→sonnet (see that repo's `docs/reference/quota-economics.md`).
  Absent field = `reasoning`. META iterations audit classification quality.

## File format

```markdown
---
from: claude-opus-4-7
to: gemini
project: /etc/nixos/mandragora    # absolute path or "global" if cross-project
created: 2026-04-26T14:32:00Z
status: open                       # open | consumed
consumed_at:                       # set by /pickup
---

## Task
One paragraph: what we're doing and why.

## State
- Files touched: paths (or "none")
- Worktrees: branch/path (or "none")
- Rebuild status: green | dirty | not attempted

## Next step
Literal next action the receiver should take.

## Open questions
- ... (or "none")

## Pointers
- file:line references that matter (or "none")
```

## Receiver behavior

- On `/pickup`, look for `status: open` files where `to:` matches your
  agent ID, sorted newest-first. Read the latest, then flip its
  frontmatter to `status: consumed` and stamp `consumed_at`.
- If multiple are open, surface the list to the user and ask which to
  pick up.
- A handoff is advisory context, not a command — verify the on-disk
  state still matches "Files touched" and "Rebuild status" before
  acting.

## AI Bridge directories

All agents share context through:

- `~/.ai-shared/handoffs/` — explicit baton-passes between agents
- `~/.ai-shared/memory/` — Claude's auto-memory, readable by every agent
- `~/.ai-shared/rules/` — additional constraints
- `~/.ai-shared/templates/` — reusable patterns

When you discover a system quirk or define a new pattern, document it in
the bridge so other agents can read it.

## Session-checkpoint vs baton-pass (added 2026-05-31)

A hand-off has two distinct modes. Both legitimate, but they must be
labelled so the next reader knows what they're reading.

- **Baton-pass** (`to: gemini`, `to: qwen`, …) — cross-agent. The next
  agent is a different model/persona. Context the new agent does not
  share must be encoded explicitly.
- **Session-checkpoint** (`to: claude`) — within-agent context flush,
  typically forced by context-window exhaustion mid-task. The next
  reader is *the same agent in a fresh session* with no memory.

Both formats are identical. The distinction is in the frontmatter
`kind:` field (added 2026-05-31):

```yaml
kind: baton       # cross-agent
kind: checkpoint  # same-agent context flush
```

If `kind:` is omitted, infer from `to:` (`to: claude` → `checkpoint`
unless the task explicitly says "Claude in a different role").

**Why this matters:** A baton must encode everything; a checkpoint may
lean on the receiving Claude's ability to re-read project memory,
STATE.md, and `git log`. Mislabelling causes either over-stuffing (baton
treated as checkpoint, next agent missing context) or under-stuffing
(checkpoint treated as baton, redundant scaffolding).

## Hand-off chaining (added 2026-05-31)

A pickup MUST read the most recent prior hand-off for the same project
before re-deriving state from scratch. The chain reduces context
re-discovery cost and prevents the "each pickup re-reads `git log`"
ballooning pattern (audit finding 2026-05-31: hand-off file size was
growing +51.6% because chains were broken).

If the prior hand-off contradicts current on-disk state, **trust
on-disk** and note the divergence in the new hand-off's "State" section
under a `## Divergence from prior` heading.

If no prior hand-off exists for the project, say so in the new
hand-off's task paragraph.
