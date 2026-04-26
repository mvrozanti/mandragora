---
type: module
layer: desktop
tags: [module, desktop, lighting, hyprland]
path: modules/desktop/keyledsd.nix
---

# keyledsd.nix

RGB lighting daemon for the Logitech G Pro keyboard, wired to Hyprland workspace events.

## Role
- Custom `keyleds-ticpu` overlay (fork from ticpu/keyleds) with the in-tree `keyleds-extra-input.patch`.
- Reads effect files from `snippets/keyledsd-effects/`.
- Wraps [[../../scripts/keyleds-workspace-watcher]] as a `writeShellApplication` that subscribes to Hyprland's IPC socket.

## Connections
- Up: [[../_index|Modules]]
- Pairs with: [[hyprland]] (workspace events feed the watcher), [[openrgb]] (mutually exclusive on this keyboard — see openrgb's note)
- Scripts: [[../../scripts/keyleds-workspace-watcher]]
- Configs: [[../../configs/keyledsd]]
