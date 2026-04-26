---
type: module
layer: desktop
tags: [module, desktop, login]
path: modules/desktop/sddm.nix
---

# sddm.nix

Wayland-native SDDM with the custom Mandragora theme. Auto-logs `m` into Hyprland.

## Role
- `kdePackages.sddm`, `wayland.enable = true`.
- `theme = "sddm-mandragora"` ([[../../packages/sddm-mandragora]]).
- Autologin user `m`, `defaultSession = "hyprland"`.

## Connections
- Up: [[../_index|Modules]]
- Pairs with: [[hyprland]] (target session)
- Packages: [[../../packages/sddm-mandragora]]
- Touches: [[../../concepts/wayland]]
