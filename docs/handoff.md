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
  after pickup.

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
