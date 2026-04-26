---
type: concept
tags: [concept, zx-dirs, shell]
---

# zX directory shortcuts

A single-letter → directory map. Both Zsh and lf consume it from one source — [[../modules/user/zx-dirs]] — so adding a shortcut updates both at once.

In Zsh: `zX` (cd alias). In lf: `gX` (jump keybinding). Edit the source, rebuild, both move together.

## Touched by

- [[../modules/user/zx-dirs]] — the source of truth
- [[../modules/user/zsh]] — builds `z<letter>` aliases
- [[../modules/user/lf]] — builds `g<letter>` keybindings

See: [[language-purity]]
