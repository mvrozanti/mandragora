# GEMINI.md — Mandragora NixOS (Gemini CLI Addendum)

**Read [`AGENTS.md`](./AGENTS.md) first.** It is the canonical source for
hard constraints, the impermanence rule, the multi-agent safety rule, the
Edit → Rebuild → Verify workflow, the AI bridge, and per-agent policy
variances. This file holds only the Gemini-specific delta.

---

## AI Bridge Specifics

The AI bridge at `~/.ai-shared/` is shared by all agents (Claude, Gemini,
local Qwen, etc.). Gemini-specific notes:

- **Tasks:** read and update `~/.ai-shared/TASKS.md` to track active goals,
  completed work, and handoffs. Do not silo tasks in your own memory.
- **Skills:** check `~/.ai-shared/skills/` for `SKILL.md` files describing
  multi-agent procedures. Create new `SKILL.md` files when establishing a
  new multi-agent workflow.
- **Rules / templates:** follow constraints defined in `~/.ai-shared/rules/`
  and `~/.ai-shared/templates/`.
- **Knowledge transfer:** if you discover a system quirk or define a new
  pattern, document it in the bridge so other models read it on their next
  session.
- **Git safety:** when promoting a file like `AGENTS.md` to the bridge,
  **copy** it (or symlink the bridge entry to the canonical path). Do not
  move the original out of version control.

---

## Rebuild Mandate

Run `mandragora-switch` immediately after every file modification.
Autonomous commit is authorized for this purpose (this is the per-agent
policy variance noted in `AGENTS.md`). Use the `!` flag to skip the
interactive diff editor:

```
mandragora-switch !
```

This mandate is Gemini-specific. Other agents (Claude Code, local Qwen)
follow the default policy: do not commit without explicit user instruction.
