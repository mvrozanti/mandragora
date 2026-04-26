---
type: module
layer: user
tags: [module, user, bar, audio]
path: modules/user/waybar.nix
---

# waybar.nix

The Hyprland top bar — mpd status, weather, volume, workspaces.

## Role
- Reads `snippets/waybar-style.css` via `builtins.readFile`.
- Calls scripts from `.config/waybar/scripts/` (mpd-status, volume-ramp, weather).
- Consumes `weather/api_key` from [[../core/secrets]].

## Connections
- Up: [[../_index|Modules]]
- Imported by: [[home]]
- Pairs with: [[../desktop/hyprland]] (the bar lives on Hyprland), [[services]] (mpd source), [[../core/secrets]] (weather key)
- Configs: [[../../configs/waybar]]
- Touches: [[../../concepts/audio-pipeline]]
