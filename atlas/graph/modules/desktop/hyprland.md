---
type: module
layer: desktop
tags: [module, desktop, wayland, nvidia, audio]
path: modules/desktop/hyprland.nix
---

# hyprland.nix

The Wayland compositor + the audio stack + XDG portals. The biggest hub on the desktop layer.

## Role
- Enables `programs.hyprland` with XWayland.
- NVIDIA Wayland env vars: `LIBVA_DRIVER_NAME`, `GBM_BACKEND`, `__GLX_VENDOR_LIBRARY_NAME=nvidia`.
- XDG portal: `xdg-desktop-portal-hyprland` + GTK fallback.
- Pipewire (ALSA + Pulse + Jack) + Wireplumber, with [[../../configs/wireplumber|wireplumber/hdmi-default.conf]] read in.

## Connections
- Up: [[../_index|Modules]]
- Consumes: [[../core/graphics]] (NVIDIA driver presence)
- Pairs with: [[sddm]] (`defaultSession = "hyprland"`), [[keyledsd]] (workspace events), [[../user/waybar]] (top bar), [[../user/services]] (mpd via Pipewire)
- Configs: [[../../configs/hypr]], [[../../configs/wireplumber]]
- Touches: [[../../concepts/wayland]], [[../../concepts/nvidia]], [[../../concepts/audio-pipeline]]
