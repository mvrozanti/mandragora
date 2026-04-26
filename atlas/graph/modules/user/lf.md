---
type: module
layer: user
tags: [module, user, shell]
path: modules/user/lf.nix
---

# lf.nix

The `lf` file manager with a custom build (`lf-ub` patch) and `gX` keybindings sourced from [[zx-dirs]].

## Role
- Patches lf with `./lf-autodirsize.patch`.
- Reads [[zx-dirs]] for `g<letter>` directory keybindings.
- Wraps `.config/lf/{preview,cleaner,opener}` as shell scripts via `builtins.readFile`.

## Connections
- Up: [[../_index|Modules]]
- Imported by: [[home]]
- Pairs with: [[zsh]] (shared zX state), [[zx-dirs]] (the source)
- Configs: [[../../configs/lf]]
- Touches: [[../../concepts/zx-dirs]], [[../../concepts/language-purity]]
