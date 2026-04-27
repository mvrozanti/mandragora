---
type: script
tags: [script, workflow]
path: .local/bin/mandragora-switch.sh
---

# mandragora-switch

The master ritual: `git fetch` → rebase if behind → `git add -A` → diff editor for commit message (`!` to skip) → `sudo nixos-rebuild switch` → `git push`. Guards against a concurrent `nixos-rebuild` via `pgrep` at startup.

Wrapped by: [[../modules/user/home]]
Touches: [[../concepts/rebuild-workflow]], [[../concepts/agent-worktrees]], [[../concepts/declarative-supremacy]]
