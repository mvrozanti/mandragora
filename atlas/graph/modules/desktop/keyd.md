---
type: module
layer: desktop
tags: [module, desktop, input]
path: modules/desktop/keyd.nix
---

# keyd.nix

Kernel-level keyboard remapping. CapsLock ↔ Esc on every keyboard plugged in.

## Role
- `services.keyd` with wildcard `ids = [ "*" ]`.
- One swap rule, applied universally.

## Connections
- Up: [[../_index|Modules]]
- Pairs with: [[ydotool]] (synthetic input), [[keyledsd]] (RGB on the same keyboards)
