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

# Function to get all connected outputs (exclude disconnected ones)
get_outputs() {
    xrandr --current | grep " connected" | awk '{print $1}'
}

# Function to set brightness using xrandr
set_brightness_xrandr() {
    local percent=$1
    # Convert percent (0-100) to float (0.0-1.0) with bc
    local float_val
    float_val=$(echo "scale=2; $percent / 100" | bc)

    for output in $(get_outputs); do
        xrandr --output "$output" --brightness "$float_val"
    done
}

# Function to actually change brightness (auto‑choose method)
set_brightness() {
    local percent=$1

    # Clamp between 0 and 100
    [ "$percent" -lt 0 ] && percent=0
    [ "$percent" -gt 100 ] && percent=100

    # Prefer brightnessctl if a backlight device exists, otherwise use xrandr
    if command -v brightnessctl &>/dev/null && brightnessctl -l 2>/dev/null | grep -qi backlight; then
        # Use the first backlight device found
        local device
        device=$(brightnessctl -l | grep -i backlight | head -1 | awk -F"'" '{print $2}')
        brightnessctl --device="$device" set "${percent}%" >/dev/null 2>&1
    elif command -v xrandr &>/dev/null; then
        set_brightness_xrandr "$percent"
    else
        echo "No brightness control method available (install brightnessctl or xrandr)" >&2
        exit 1
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
        set_brightness 0   # off → brightness 0% (screen black)
    fi
}

# Change mode (on/off) while keeping the stored value
changeMode() {
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
