---
type: script
tags: [script, workflow]
path: .local/bin/mandragora-switch.sh
---

# mandragora-switch

The master ritual: `git fetch` → rebase if behind → `git add -A` → diff editor for commit message (`!` to skip) → `sudo nixos-rebuild switch` → `git push`.

Internally claims a `--phase commit` lock that conflicts with every other [[mandragora-lock]].

Wrapped by: [[../modules/user/home]]
Touches: [[../concepts/rebuild-workflow]], [[../concepts/agent-locks]], [[../concepts/declarative-supremacy]]
