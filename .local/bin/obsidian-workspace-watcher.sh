#!/usr/bin/env bash
socket="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
socat -U - "UNIX-CONNECT:$socket" | while IFS= read -r line; do
    event="${line%%>>*}"
    [[ "$event" != "openwindow" ]] && continue
    data="${line#*>>}"
    addr="${data%%,*}"
    rest="${data#*,}"
    class="${rest#*,}"
    class="${class%%,*}"
    [[ "$class" != "obsidian" ]] && continue
    hyprctl dispatch workspace 41
    hyprctl dispatch focuswindow "address:0x$addr"
done
