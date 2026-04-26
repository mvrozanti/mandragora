---
name: handoff
description: Use when the user wants to pass current task context to another AI agent (Gemini, Qwen, etc.) so they can continue mid-thought. Writes a structured baton-pass to ~/.ai-shared/handoffs/. Triggered explicitly via /handoff [target-agent].
---

# handoff — Pass Context to Another Agent

## Overview

A handoff is an explicit, user-initiated baton-pass from this session to another agent. It writes a single markdown file under `~/.ai-shared/handoffs/` containing the active task, current state, next step, open questions, and any pointers the receiver needs to continue without forcing the user to re-explain.

The full protocol — file naming, frontmatter schema, status lifecycle — lives in `~/.ai-shared/AGENTS.md` under "Cross-Agent Handoff Protocol". This skill is the write side. The read side is `/pickup`.

## When to Use

- User says "handoff to gemini", "/handoff", "pass this to qwen", "let gemini take over".
- User explicitly switches agents mid-task and wants continuity.

**Do NOT use when:**
- The task is finished — there's nothing to hand off.
- The user is just asking a one-shot question of another agent (use the agent's CLI directly).
- No real context exists yet (fresh session, no decisions made) — say so and ask what to record.

## Arguments

`/handoff [target]` — `target` is a short agent ID: `gemini`, `qwen`, `claude` (different session), etc. Default: `gemini` if omitted. If unsure, ask once.

## Workflow

```
1. Resolve     target = arg or "gemini"; from = "claude-<model-suffix>"
2. Gather      Synthesize from current conversation:
                 - Task: one paragraph, what + why
                 - Files touched: scan recent edits + git status if in a repo
                 - Locks held: `mandragora-lock list` if locks may apply
                 - Rebuild status: green / dirty / not attempted
                 - Next step: literal next action
                 - Open questions
                 - Pointers: file:line references that matter
3. Draft       Show the user the full handoff content. Ask for ack/edits.
4. Write       Path: ~/.ai-shared/handoffs/<UTC-ISO>-claude-to-<target>.md
                 Timestamp format: YYYYMMDDTHHMMSSZ (no separators, sorts lexically)
                 Frontmatter: status: open
5. Confirm     Tell the user the path and that it's ready for /pickup on the
               receiving side.
```

## File Format

Match the schema in `~/.ai-shared/AGENTS.md` exactly. Example:

```markdown
---
from: claude-opus-4-7
to: gemini
project: /etc/nixos/mandragora
created: 2026-04-26T14:32:00Z
status: open
consumed_at:
---

## Task
We're tightening hyprland border colors after the 0.54 update broke
the inactive border alpha. The fix is in modules/desktop/hyprland.nix
but a layerrule snippet still references the old color name.

## State
- Files touched: modules/desktop/hyprland.nix, .config/hypr/extra.conf
- Locks held: none
- Rebuild status: dirty (edits not yet rebuilt)

## Next step
Update the `layerrule` block in .config/hypr/extra.conf line 47 to use
`col.inactive_border` instead of the deprecated `inactive_border_color`,
then run `mandragora-switch` and verify with `hyprctl configerrors`.

## Open questions
- Should `col.active_border` get the same alpha treatment, or keep it solid?

## Pointers
- modules/desktop/hyprland.nix:112 — color decl
- .config/hypr/extra.conf:47 — the stale reference
```

## Writing the Timestamp

```bash
ts=$(date -u +%Y%m%dT%H%M%SZ)
target=${1:-gemini}
path=~/.ai-shared/handoffs/${ts}-claude-to-${target}.md
mkdir -p ~/.ai-shared/handoffs
# write the file with the Write tool, not heredoc
```

The `created:` field inside the frontmatter is the same instant in standard ISO format (`date -u +%Y-%m-%dT%H:%M:%SZ`).

## Critical Rules

1. **Always show the draft first.** A handoff is a high-leverage artifact — the receiver acts on it. The user must ack before write.
2. **Ground everything in current state, not memory.** Run `git status`, `mandragora-lock list`, etc. before claiming "files touched" or "locks held". A handoff that lies about state is worse than no handoff.
3. **Be specific in "Next step".** "Continue the work" is useless. Name the file, the line, the command.
4. **Don't include secrets.** Never paste `secrets/` contents, env tokens, or credentials. Reference paths only.
5. **Don't delete or edit existing handoffs.** Append-only. If a handoff was wrong, write a new one that supersedes it (and say so in the Task paragraph).
6. **Never auto-handoff.** Only on explicit `/handoff` invocation.

## Hand-Off

After writing, report to the user:

```
Wrote handoff: ~/.ai-shared/handoffs/<filename>
  to: <target>
  task: <one-line summary>
Receiver runs /pickup (or equivalent) to claim it.
```

Then stop. Do not switch agents yourself.
