---
type: module
layer: desktop
tags: [module, desktop, input, wayland]
path: modules/desktop/ydotool.nix
---

# ydotool.nix

Wayland-friendly synthetic input — `xdotool`'s replacement.

## Role
- Enables `programs.ydotool`.
- Sets `YDOTOOL_SOCKET=/run/ydotoold/socket` system-wide.

## Connections
- Up: [[../_index|Modules]]
- Pairs with: [[keyd]] (input layer siblings), [[hyprland]] (Wayland use case)
- Touches: [[../../concepts/wayland]]
