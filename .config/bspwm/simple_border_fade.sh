#!/bin/bash
# ~/.config/bspwm/simple_border_fade.sh

HOLD_DURATION=5
HIGHLIGHT_WIDTH=4
NORMAL_WIDTH=2

# Subscribe to focus changes
bspc subscribe node_focus | while read -r _ _ _ node_id; do
    # Restore previous window to normal
    if [ -n "$prev_window" ] && [ "$prev_window" != "$node_id" ]; then
        bspc config -n "$prev_window" border_width $NORMAL_WIDTH
    fi
    
    # Apply highlight to new window
    bspc config -n "$node_id" border_width $HIGHLIGHT_WIDTH
    
    # Set timer to restore after delay
    (
        sleep $HOLD_DURATION
        # Only restore if still the same window
        current_focused=$(bspc query -N -n .focused)
        if [ "$current_focused" = "$node_id" ]; then
            bspc config -n "$node_id" border_width $NORMAL_WIDTH
        fi
    ) &
    
    prev_window="$node_id"
done