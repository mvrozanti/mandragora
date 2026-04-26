---
type: module
layer: user
tags: [module, user, services, audio]
path: modules/user/services.nix
---

# services.nix

User-level systemd services: mpd, mbsync (Hotmail), Transmission, khal sync.

## Role
- mpd from `.config/mpd/mpd.conf` (read in via `builtins.readFile`).
- mbsync wraps [[../../scripts/mbsync-hotmail-sync]].
- Transmission daemon, khal calendar sync.

## Connections
- Up: [[../_index|Modules]]
- Imported by: [[home]]
- Pairs with: [[waybar]] (mpd status display), [[../desktop/hyprland]] (Pipewire substrate)
- Configs: [[../../configs/mpd]], [[../../configs/khal]]
- Scripts: [[../../scripts/mbsync-hotmail-sync]]
- Touches: [[../../concepts/audio-pipeline]], [[../../concepts/language-purity]]
