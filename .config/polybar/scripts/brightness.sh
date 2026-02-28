#!/bin/bash

# File to store brightness state (same as your redshift file)
envFile=~/.config/polybar/scripts/env.sh
changeValue=5   # brightness increment in percent

# Load current values from env file
if [ -f "$envFile" ]; then
    . "$envFile"
fi

# Set defaults if variables are not defined
: "${BRIGHTNESS:=on}"
: "${BRIGHTNESS_VAL:=50}"

# Function to actually change brightness using available tools
set_brightness() {
    local percent=$1
    if command -v brightnessctl &>/dev/null; then
        brightnessctl set "${percent}%"
    # elif command -v xrandr &>/dev/null; then
    #     # Fallback: set gamma brightness for the first connected output
    #     local output
    #     output=$(xrandr --current | grep " connected" | awk '{print $1}' | head -1)
    #     if [ -n "$output" ]; then
    #         # Convert percent (0-100) to float (0.0-1.0)
    #         local float_val
    #         float_val=$(echo "scale=2; $percent/100" | bc)
    #         xrandr --output "$output" --brightness "$float_val"
    #     else
    #         echo "No connected output found for xrandr" >&2
    #         return 1
    #     fi
    else
        echo "No brightness control tool found (install brightnessctl)" >&2
        return 1
    fi
}

# Update env file and apply brightness
apply_brightness() {
    local new_mode=$1
    local new_val=$2

    # Update or add BRIGHTNESS line
    if grep -q "^BRIGHTNESS=" "$envFile"; then
        sed -i "s/^BRIGHTNESS=.*/BRIGHTNESS=$new_mode/" "$envFile"
    else
        echo "BRIGHTNESS=$new_mode" >> "$envFile"
    fi

    # Update or add BRIGHTNESS_VAL line
    if grep -q "^BRIGHTNESS_VAL=" "$envFile"; then
        sed -i "s/^BRIGHTNESS_VAL=.*/BRIGHTNESS_VAL=$new_val/" "$envFile"
    else
        echo "BRIGHTNESS_VAL=$new_val" >> "$envFile"
    fi

    # Apply the brightness
    if [ "$new_mode" = "on" ]; then
        set_brightness "$new_val"
    else
        set_brightness 0   # off → brightness 0%
    fi
}

# Change mode (on/off) while keeping the stored value
changeMode() {
    # $1 = old mode (unused), $2 = new mode
    apply_brightness "$2" "$BRIGHTNESS_VAL"
}

# Change brightness value (increase/decrease)
changeBrightness() {
    local new_val=$2
    # Clamp between 0 and 100
    [ "$new_val" -lt 0 ] && new_val=0
    [ "$new_val" -gt 100 ] && new_val=100

    # If currently off, turn on first
    if [ "$BRIGHTNESS" != "on" ]; then
        changeMode "$BRIGHTNESS" "on"
    else
        apply_brightness "on" "$new_val"
    fi
}

# Default to 'brightness' when no argument is given
case ${1:-brightness} in
    toggle)
        if [ "$BRIGHTNESS" = "on" ]; then
            changeMode "$BRIGHTNESS" "off"
        else
            changeMode "$BRIGHTNESS" "on"
        fi
        ;;
    increase)
        new_val=$((BRIGHTNESS_VAL + changeValue))
        changeBrightness "$BRIGHTNESS_VAL" "$new_val"
        ;;
    decrease)
        new_val=$((BRIGHTNESS_VAL - changeValue))
        changeBrightness "$BRIGHTNESS_VAL" "$new_val"
        ;;
    brightness)
        if [ "$BRIGHTNESS" = "on" ]; then
            printf "%d%%" "$BRIGHTNESS_VAL"
        else
            printf " "   # blank when off (like your redshift script)
        fi
        ;;
    *)
        echo "Usage: $0 [toggle|increase|decrease|brightness]"
        exit 1
        ;;
esac
