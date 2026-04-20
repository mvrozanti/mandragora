#!/usr/bin/env bash
layouts=(us ru)
current=$(hyprctl getoption input:kb_layout | awk '/str:/{print $2}')
for i in "${!layouts[@]}"; do
    if [[ "${layouts[$i]}" == "$current" ]]; then
        next="${layouts[$(( (i+1) % ${#layouts[@]} ))]}"
        break
    fi
done
next="${next:-${layouts[0]}}"
hyprctl keyword input:kb_layout "$next"
notify-send "Keyboard Layout" "$next"
