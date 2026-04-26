---
type: module
layer: desktop
tags: [module, desktop, gaming]
path: modules/desktop/steam.nix
---

# steam.nix

Steam + Proton-GE for gaming.

## Role
- `programs.steam.enable`.
- `remotePlay.openFirewall = true`.
- `extraCompatPackages = [ proton-ge-bin ]`.

## Connections
- Up: [[../_index|Modules]]
- Pairs with: [[../core/graphics]] (32-bit graphics enabled), [[minecraft-desktop|minecraft]] (gaming sibling)
- Touches: [[../../concepts/nvidia]]
