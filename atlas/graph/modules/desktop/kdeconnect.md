---
type: module
layer: desktop
tags: [module, desktop]
path: modules/desktop/kdeconnect.nix
---

# kdeconnect.nix

Phone ↔ desktop sync via KDE Connect.

## Role
- Enables `programs.kdeconnect` with the KDE Frameworks 6 package.
- Defines a user-level `kdeconnectd` systemd unit tied to `graphical-session.target`.

## Connections
- Up: [[../_index|Modules]]
- Pairs with: [[hyprland]] (graphical session target)
