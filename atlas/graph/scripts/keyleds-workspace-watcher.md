---
type: script
tags: [script, lighting, hyprland]
path: .local/bin/keyleds-workspace-watcher.sh
---

# keyleds-workspace-watcher

Subscribes to Hyprland's IPC socket and emits keyleds effect changes per workspace.

Wrapped by: [[../modules/desktop/keyledsd]] (as a `writeShellApplication` with socat/jq/hyprland in `runtimeInputs`)
Pairs with: [[../modules/desktop/hyprland]]
