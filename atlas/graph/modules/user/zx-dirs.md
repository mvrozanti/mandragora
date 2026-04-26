---
type: module
layer: user
tags: [module, user, shell, zx-dirs]
path: modules/user/zx-dirs.nix
---

# zx-dirs.nix

The single source of truth for `zX` directory shortcuts. A pure attrset that both [[zsh]] and [[lf]] import.

## Role
- Maps a single letter → an absolute path.
- Imported via `import ./zx-dirs.nix` — no module wrapper, no system effect on its own.

## Connections
- Up: [[../_index|Modules]]
- Consumed by: [[zsh]] (builds `z<letter>` aliases), [[lf]] (builds `g<letter>` keybindings)
- Touches: [[../../concepts/zx-dirs]]
