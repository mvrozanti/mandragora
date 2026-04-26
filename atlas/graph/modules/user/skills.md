---
type: module
layer: user
tags: [module, user, ai, skills]
path: modules/user/skills.nix
---

# skills.nix

50+ BMAD skills + handoff/pickup/nrp installed into Claude Code via `~/.claude/skills/`.

## Role
- Maps every skill from flake inputs (BMAD Method, CIS, TEA, Builder) into the user's Claude config.
- Adds in-tree skills from `agent-skills/` (`handoff`, `pickup`, `nrp`).

## Connections
- Up: [[../_index|Modules]]
- Imported by: [[home]]
- Pairs with: [[../core/ai-local]] (local AI sibling), [[bots]]
- Touches: [[../../concepts/skill-ecosystem]], [[../../concepts/ai-stack]]
