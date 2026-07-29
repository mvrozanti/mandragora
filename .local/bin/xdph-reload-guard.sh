#!/usr/bin/env bash
socket="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

socat -U - "UNIX-CONNECT:$socket" | while IFS= read -r line; do
    [[ "$line" == configreloaded* ]] || continue
    systemctl --user try-restart xdg-desktop-portal.service xdg-desktop-portal-hyprland.service
done
