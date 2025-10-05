#!/bin/bash

# Font invert toggle script for polybar
# Solves readability issues with pywal + picom transparency/blur

PDIR="$HOME/.config/polybar"
CONFIG="$PDIR/config.ini"
INVERT_FILE="$PDIR/.font-invert"

# Function to get actual color value from xrdb or return hex
get_color_value() {
    local color_ref="$1"
    if [[ "$color_ref" =~ \$\{xrdb:color([0-9]+)\} ]]; then
        # Get the actual color from xrdb
        xrdb -query | grep "color${BASH_REMATCH[1]}:" | awk '{print $2}'
    else
        # Return as-is if it's already a hex color
        echo "$color_ref"
    fi
}

# Function to invert a hex color
invert_color() {
    local color="$1"
    # Remove # if present
    color="${color#\#}"
    
    # Convert to RGB
    local r=$((16#${color:0:2}))
    local g=$((16#${color:2:2}))
    local b=$((16#${color:4:2}))
    
    # Invert each component
    r=$((255 - r))
    g=$((255 - g))
    b=$((255 - b))
    
    # Convert back to hex
    printf "#%02x%02x%02x" $r $g $b
}

# Check if invert mode is currently active
if [[ -f "$INVERT_FILE" ]]; then
    # Currently inverted, switch back to normal
    rm "$INVERT_FILE"
    echo "Switching to normal font colors..."
    
    # Restore original foreground colors
    sed -i 's/foreground = #.*/foreground = ${xrdb:color15}/' "$CONFIG"
    sed -i 's/foreground-alt = #.*/foreground-alt = #555/' "$CONFIG"
    
else
    # Currently normal, switch to inverted
    touch "$INVERT_FILE"
    echo "Switching to inverted font colors..."
    
    # Get current foreground colors and invert them
    current_fg=$(grep "foreground = " "$CONFIG" | head -1 | sed 's/.*= //')
    current_fg_alt=$(grep "foreground-alt = " "$CONFIG" | head -1 | sed 's/.*= //')
    
    # Get actual color values
    actual_fg=$(get_color_value "$current_fg")
    actual_fg_alt=$(get_color_value "$current_fg_alt")
    
    # Invert the colors
    inverted_fg=$(invert_color "$actual_fg")
    inverted_fg_alt=$(invert_color "$actual_fg_alt")
    
    # Apply inverted colors
    sed -i "s/foreground = .*/foreground = $inverted_fg/" "$CONFIG"
    sed -i "s/foreground-alt = .*/foreground-alt = $inverted_fg_alt/" "$CONFIG"
fi

# Restart polybar
polybar-msg cmd restart
