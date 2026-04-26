---
type: concept
tags: [concept, audio]
---

# Audio pipeline

Pipewire (with ALSA + Pulse + Jack shims) is the kernel of audio. Wireplumber sets policy. mpd plays music. Waybar shows status.

## Flow

[[../modules/desktop/hyprland]] enables Pipewire/Wireplumber → [[../configs/wireplumber]] policy file selects HDMI default → [[../modules/user/services]] runs mpd → [[../configs/mpd]] points at the right sink → [[../modules/user/waybar]] reads `mpc status` → [[../scripts/cycle-audio-output]] cycles sinks on demand.

## Touched by

- [[../modules/desktop/hyprland]]
- [[../modules/user/services]]
- [[../modules/user/waybar]]
- [[../scripts/cycle-audio-output]]
- [[../configs/wireplumber]], [[../configs/mpd]], [[../configs/ncmpcpp]], [[../configs/glava]]
