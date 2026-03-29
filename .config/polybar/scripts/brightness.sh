#!/bin/bash

# ============================================================
# Brightness control script for Polybar (like your redshift script)
# Never sets brightness to 0 – "off" means full brightness (100%).
# ============================================================

envFile=~/.config/polybar/scripts/env.sh
changeValue=5          # brightness increment in percent
MIN_BRIGHTNESS=20       # lowest allowed brightness (never 0)

# Load current values from env file
if [ -f "$envFile" ]; then
    . "$envFile"
fi

# Set defaults if variables are not defined
: "${BRIGHTNESS:=on}"
: "${BRIGHTNESS_VAL:=50}"

# Ensure stored value is at least MIN_BRIGHTNESS
if [ "$BRIGHTNESS_VAL" -lt "$MIN_BRIGHTNESS" ]; then
    BRIGHTNESS_VAL=$MIN_BRIGHTNESS
fi

# ---------- Brightness control backends ----------
# Get all connected outputs for xrandr
get_xrandr_outputs() {
    xrandr --current | grep " connected" | awk '{print $1}'
}

# Set brightness using xrandr (software gamma)
set_brightness_xrandr() {
    local percent=$1
    local float_val
    float_val=$(echo "scale=2; $percent / 100" | bc)
    for output in $(get_xrandr_outputs); do
        xrandr --output "$output" --brightness "$float_val"
    done
}

# Main brightness setter – auto‑chooses method
set_brightness() {
    local percent=$1

    # Clamp to 0-100 just in case, though we never pass <1 or >100
    [ "$percent" -lt 0 ] && percent=0
    [ "$percent" -gt 100 ] && percent=100

    # Prefer brightnessctl if a backlight device exists, otherwise use xrandr
    if command -v brightnessctl &>/dev/null && brightnessctl -l 2>/dev/null | grep -qi backlight; then
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

# ---------- Environment file management ----------
update_env() {
    local mode=$1
    local value=$2

    # Update BRIGHTNESS line
    if grep -q "^BRIGHTNESS=" "$envFile"; then
        sed -i "s/^BRIGHTNESS=.*/BRIGHTNESS=$mode/" "$envFile"
    else
        echo "BRIGHTNESS=$mode" >> "$envFile"
    fi

    # Update BRIGHTNESS_VAL line
    if grep -q "^BRIGHTNESS_VAL=" "$envFile"; then
        sed -i "s/^BRIGHTNESS_VAL=.*/BRIGHTNESS_VAL=$value/" "$envFile"
    else
        echo "BRIGHTNESS_VAL=$value" >> "$envFile"
    fi
}

# Change only the mode (on/off) – keeps stored value unchanged
set_mode() {
    local new_mode=$1

    if [ "$new_mode" = "on" ]; then
        # Turn on: apply stored value (ensuring it's ≥ MIN_BRIGHTNESS)
        if [ "$BRIGHTNESS_VAL" -lt "$MIN_BRIGHTNESS" ]; then
            BRIGHTNESS_VAL=$MIN_BRIGHTNESS
        fi
        set_brightness "$BRIGHTNESS_VAL"
    else
        # Turn off: set brightness to 100% (full) without changing stored value
        set_brightness 100
    fi

    # Update env file with the new mode (value unchanged)
    update_env "$new_mode" "$BRIGHTNESS_VAL"
}

# Change the brightness value (always turns on if needed)
set_value() {
    local new_val=$1

    # Clamp to allowed range
    [ "$new_val" -lt "$MIN_BRIGHTNESS" ] && new_val=$MIN_BRIGHTNESS
    [ "$new_val" -gt 100 ] && new_val=100

    # Update stored value
    BRIGHTNESS_VAL=$new_val

    # Apply brightness (this also implicitly sets mode to 'on')
    set_brightness "$BRIGHTNESS_VAL"

    # Update env file (mode = on, value = new_val)
    update_env "on" "$BRIGHTNESS_VAL"
}

# ---------- Command dispatch ----------
case ${1:-brightness} in
    toggle)
        if [ "$BRIGHTNESS" = "on" ]; then
            set_mode "off"
        else
            set_mode "on"
        fi
        ;;
    increase)
        new_val=$((BRIGHTNESS_VAL + changeValue))
        set_value "$new_val"
        ;;
    decrease)
        new_val=$((BRIGHTNESS_VAL - changeValue))
        set_value "$new_val"
        ;;
    brightness)
        if [ "$BRIGHTNESS" = "on" ]; then
            printf "%d%%" "$BRIGHTNESS_VAL"
        else
            printf " "   # blank when off (like redshift)
        fi
        ;;
    *)
        echo "Usage: $0 [toggle|increase|decrease|brightness]"
        exit 1
        ;;
esac
