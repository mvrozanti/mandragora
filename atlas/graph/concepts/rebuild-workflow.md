---
type: concept
tags: [concept, workflow]
---

# Rebuild workflow

The only way to apply a change is `mandragora-switch` — fetch → rebase → stage → review diff → rebuild → push. Markdown-only changes use `mandragora-commit-push` (skip rebuild).

Aliases: `nrc` → switch, `nrs` → switch with `!` (no diff editor), `nrp` → commit-push, `nrb` → boot, `nrt` → test.

## Touched by

- [[../scripts/mandragora-switch]] — the master ritual
- [[../scripts/mandragora-commit-push]] — docs-only
- [[../scripts/mandragora-diff]] — the staged-diff review step
- [[agent-locks]] — `phase=commit` is exclusive
- [[declarative-supremacy]] — what this enforces

See: [[../../architecture]]
