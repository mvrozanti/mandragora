---
status: 'retired'
superseded_by: '../AGENTS.md'
date_retired: '2026-04-25'
---

# Project Context for AI Agents — RETIRED

This file used to hold an LLM-optimized rules distillate (38 rules, ~6 KB)
that paraphrased `AGENTS.md`. It has been retired because:

- Every rule update required a triple-write across `AGENTS.md`, `CLAUDE.md`,
  and this file.
- Drift was already happening (workflow step 4 said three different things
  across the three files).
- The "LLM-optimized" framing didn't pay off — agents read `AGENTS.md` fine.

## Where to look now

| You want                        | Read                                      |
| ------------------------------- | ----------------------------------------- |
| Hard constraints / non-negotiables | [`../AGENTS.md`](../AGENTS.md)         |
| Impermanence rule               | [`../AGENTS.md`](../AGENTS.md) §"The Impermanence Rule" + [`../modules/core/impermanence.nix`](../modules/core/impermanence.nix) |
| Edit → Rebuild → Verify workflow | [`../AGENTS.md`](../AGENTS.md) §"The Edit → Rebuild → Verify → Commit Workflow" |
| Per-agent policy variances      | [`../AGENTS.md`](../AGENTS.md) §"Per-Agent Policy Variances" |
| Claude-specific delta           | [`../CLAUDE.md`](../CLAUDE.md)            |
| Gemini-specific delta           | [`../GEMINI.md`](../GEMINI.md)            |
| AI bridge (`~/.ai-shared/`)     | [`../AGENTS.md`](../AGENTS.md) §"AI Bridge" |
| Architecture overview           | [`./architecture.md`](./architecture.md) (AI-facing) + [`../atlas/architecture.md`](../atlas/architecture.md) (human-facing) |
| Source tree                     | [`./source-tree-analysis.md`](./source-tree-analysis.md) |
| Day-to-day dev workflow         | [`./development-guide.md`](./development-guide.md) |

If you are an agent and you previously loaded `project-context.md` first,
load `../AGENTS.md` instead. The content has not been deleted — it has been
consolidated into AGENTS.md (canonical) plus CLAUDE.md / GEMINI.md (per-agent
deltas).
