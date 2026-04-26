---
type: module
layer: user
tags: [module, user, shell]
path: modules/user/zsh.nix
---

# zsh.nix

Zsh + Powerlevel10k + the **`zX` directory shortcuts** that share state with [[lf]].

## Role
- Reads [[zx-dirs]] for `zX` aliases (single source of truth).
- 1B-line history, `extendedglob`, prompt theme.
- Reads `.config/zsh/zshrc.zsh` + `.config/zsh/p10k.zsh` via `builtins.readFile`.

## Connections
- Up: [[../_index|Modules]]
- Imported by: [[home]]
- Pairs with: [[lf]] (also imports `zx-dirs`), [[zx-dirs]] (the source)
- Configs: [[../../configs/zsh]]
- Touches: [[../../concepts/zx-dirs]], [[../../concepts/language-purity]]
