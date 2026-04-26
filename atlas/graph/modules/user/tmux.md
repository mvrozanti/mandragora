---
type: module
layer: user
tags: [module, user, shell]
path: modules/user/tmux.nix
---

# tmux.nix

`tmux` with the in-tree `.config/tmux/tmux.conf`.

## Role
- Reads `.config/tmux/tmux.conf` via `builtins.readFile`.

## Connections
- Up: [[../_index|Modules]]
- Imported by: [[home]]
- Configs: [[../../configs/tmux]]
- Touches: [[../../concepts/language-purity]]
