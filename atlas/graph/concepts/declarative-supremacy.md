---
type: concept
tags: [concept, philosophy]
---

# Declarative supremacy

Every system change is a Nix expression (non-negotiable #1). No `pacman -S`, no `chmod`, no manual `systemctl enable`. If it's worth changing, it gets Nixified.

Reproducibility from scratch in <30 minutes is a hard requirement.

## Touched by

Effectively every node in this graph — but the most direct manifestations:

- [[../modules/_index|All modules]]
- [[../modules/audits/default]] — even the audit scripts are wrapped declaratively
- [[rebuild-workflow]] — the only way to apply changes
- [[language-purity]] — non-Nix code still goes through Nix

See: [[../../non-negotiables]]
