#!/usr/bin/env bash

# Polybar script for Airtime/Smoke Timer
# Syncs with Android app via Abacus API
# Uses local cache to handle intermittent Abacus unavailability
#
# Usage:
#   ./polybar-airtime-script.sh              # Display emoji
#   ./polybar-airtime-script.sh click-left   # Lock timer
#   ./polybar-airtime-script.sh click-middle # Show remaining time

# Configuration
ABACUS_BASE_URL="https://abacus.jasoncameron.dev"
ABACUS_NAMESPACE="airtime"
# Place name - hardcoded to "Unknown" (must match Android app's STATE_PLACE)
PLACE_NAME="Unknown"

ADMIN_KEYS_FILE="/tmp/smoke_timer_admin_keys"  # Store admin keys for writing to Abacus
CACHE_DIR="/tmp/smoke_timer_cache"
CACHE_TTL=30  # Cache TTL in seconds

# Ensure cache directory exists
mkdir -p "$CACHE_DIR" 2>/dev/null || true

# Cache helper functions
cache_get() {
    local key="$1"
    local cache_file="${CACHE_DIR}/${key}"
    if [ -f "$cache_file" ]; then
        local timestamp=$(stat -c %Y "$cache_file" 2>/dev/null || echo "0")
        local now=$(date +%s)
        local age=$((now - timestamp))
        if [ "$age" -lt "$CACHE_TTL" ]; then
            cat "$cache_file"
            return 0
        fi
    fi
    return 1
}

cache_set() {
    local key="$1"
    local value="$2"
    local cache_file="${CACHE_DIR}/${key}"
    echo "$value" > "$cache_file" 2>/dev/null || true
}

# Abacus API helper functions
abacus_get() {
    local key="$1"
    local url="${ABACUS_BASE_URL}/get/${ABACUS_NAMESPACE}/${key}"
    local response=$(curl -s --connect-timeout 5 --max-time 5 "$url" 2>/dev/null)
    
    # Check if response is empty
    if [ -z "$response" ]; then
        # Try cache
        cache_get "$key" && return 0
        return 1
    fi
    
    # Check if response is a JSON error
    if echo "$response" | grep -q '"error"'; then
        # Check if it's a rate limit error
        if echo "$response" | grep -q "Too many requests"; then
            # Try cache
            cache_get "$key" && return 0
            return 1
        fi
        # For other errors like "Key not found", try cache
        cache_get "$key" && return 0
        return 1
    fi
    
    # Check if response is JSON with "value" field (e.g., {"value": 123})
    if echo "$response" | grep -q '"value"'; then
        # Extract value from JSON using grep - try multiple patterns
        local value=$(echo "$response" | grep -oE '"value"\s*:\s*[0-9]+' | grep -oE '[0-9]+')
        if [ -z "$value" ]; then
            # Try without spaces
            value=$(echo "$response" | grep -oE '"value":[0-9]+' | grep -oE '[0-9]+')
        fi
        if [ -n "$value" ]; then
            # Cache the value
            cache_set "$key" "$value"
            echo "$value"
            return 0
        fi
    fi
    
    # Check if response is plain numeric (backward compatibility)
    if echo "$response" | grep -qE '^[0-9]+$'; then
        # Cache the value
        cache_set "$key" "$response"
        echo "$response"
        return 0
    fi
    
    # If response is "null" or other non-numeric, try cache
    if [ "$response" = "null" ] || [ "$response" = "{}" ]; then
        cache_get "$key" && return 0
        return 1
    fi
    
    # For other cases, return as-is and cache it
    cache_set "$key" "$response"
    echo "$response"
    return 0
}

abacus_create() {
    local key="$1"
    local url="${ABACUS_BASE_URL}/create/${ABACUS_NAMESPACE}/${key}"
    local response=$(curl -s --connect-timeout 5 --max-time 5 -X POST "$url" 2>/dev/null)
    
    # Check if response contains an admin key
    if [ -n "$response" ]; then
        # Try to extract admin key from JSON or use as-is
        local admin_key=$(echo "$response" | grep -oE '"admin_key"\s*:\s*"[^"]+"' | grep -oE '"[^"]+"' | tr -d '"')
        if [ -z "$admin_key" ]; then
            # Not JSON, might be plain text admin key
            admin_key=$(echo "$response" | grep -v "error" | head -1)
        fi
        if [ -n "$admin_key" ] && [ "$admin_key" != "null" ]; then
            echo "$admin_key"
            return 0
        fi
    fi
    return 1
}

abacus_get_admin_key() {
    local key="$1"
    # Check if we have a stored admin key
    if [ -f "$ADMIN_KEYS_FILE" ]; then
        grep "^${key}=" "$ADMIN_KEYS_FILE" | cut -d'=' -f2-
    fi
}

abacus_store_admin_key() {
    local key="$1"
    local admin_key="$2"
    # Store admin key in file
    if [ ! -f "$ADMIN_KEYS_FILE" ]; then
        touch "$ADMIN_KEYS_FILE"
        chmod 600 "$ADMIN_KEYS_FILE"
    fi
    # Remove old entry if exists
    grep -v "^${key}=" "$ADMIN_KEYS_FILE" > "${ADMIN_KEYS_FILE}.tmp" 2>/dev/null || true
    echo "${key}=${admin_key}" >> "${ADMIN_KEYS_FILE}.tmp"
    mv "${ADMIN_KEYS_FILE}.tmp" "$ADMIN_KEYS_FILE"
}

abacus_set() {
    local key="$1"
    local value="$2"
    # Use query parameter format (matches Android app)
    local url="${ABACUS_BASE_URL}/set/${ABACUS_NAMESPACE}/${key}?value=${value}"
    
    # Get admin key (try stored first, then create if needed)
    local admin_key=$(abacus_get_admin_key "$key")
    if [ -z "$admin_key" ]; then
        # Try to create counter to get admin key
        admin_key=$(abacus_create "$key")
        if [ -n "$admin_key" ]; then
            abacus_store_admin_key "$key" "$admin_key"
        else
            # Can't write without admin key, fail
            return 1
        fi
    fi
    
    # Use admin key to write
    local response=$(curl -s --connect-timeout 5 --max-time 5 -X POST \
        -H "Authorization: Bearer ${admin_key}" \
        "$url" 2>/dev/null)
    
    # Check if we got a 401 (invalid token) - clear admin key and retry
    if echo "$response" | grep -q "401\|invalid\|token"; then
        # Clear stored admin key
        grep -v "^${key}=" "$ADMIN_KEYS_FILE" > "${ADMIN_KEYS_FILE}.tmp" 2>/dev/null || true
        mv "${ADMIN_KEYS_FILE}.tmp" "$ADMIN_KEYS_FILE" 2>/dev/null || true
        # Try to recreate
        admin_key=$(abacus_create "$key")
        if [ -n "$admin_key" ]; then
            abacus_store_admin_key "$key" "$admin_key"
            # Retry with new key
            curl -s --connect-timeout 5 --max-time 5 -X POST \
                -H "Authorization: Bearer ${admin_key}" \
                "$url" >/dev/null 2>&1
            return $?
        fi
        return 1
    fi
    
    # If successful, update cache
    if [ $? -eq 0 ] || [ -z "$response" ]; then
        cache_set "$key" "$value"
    fi
    
    # Check if successful (2xx response)
    if echo "$response" | grep -qE '^[0-9]+$' || [ -z "$response" ]; then
        return 0
    fi
    return 1
}

abacus_track() {
    local key="$1"
    local url="${ABACUS_BASE_URL}/hit/${ABACUS_NAMESPACE}/${key}"
    curl -s --connect-timeout 5 --max-time 5 "$url" >/dev/null 2>&1
}

# Get current state directly from Abacus (with cache fallback)
get_state_from_abacus() {
    # Get lock state from Abacus - source of truth
    local locked_value=$(abacus_get "${PLACE_NAME}_is_locked")
    if [ $? -ne 0 ] || [ -z "$locked_value" ]; then
        # Abacus unavailable or key not found - try cache
        locked_value=$(cache_get "${PLACE_NAME}_is_locked" 2>/dev/null || echo "")
        if [ -z "$locked_value" ]; then
            # No cache either - default to unlocked (key doesn't exist yet)
            locked_value="0"
        fi
    fi
    
    # Get lock end timestamp from Abacus
    local end_time=$(abacus_get "${PLACE_NAME}_lock_end_timestamp")
    if [ $? -ne 0 ] || [ -z "$end_time" ] || [ "$end_time" = "0" ]; then
        # Try cache
        end_time=$(cache_get "${PLACE_NAME}_lock_end_timestamp" 2>/dev/null || echo "0")
        if [ -z "$end_time" ] || [ "$end_time" = "0" ]; then
            end_time=0
        fi
    fi
    
    # Convert from milliseconds to seconds if needed
    if [ "$end_time" -gt 10000000000 ] 2>/dev/null; then
        end_time=$((end_time / 1000))
    fi
    
    # Get increment from Abacus
    local increment=$(abacus_get "${PLACE_NAME}_increment")
    if [ $? -ne 0 ] || [ -z "$increment" ]; then
        # Try cache
        increment=$(cache_get "${PLACE_NAME}_increment" 2>/dev/null || echo "0")
        if [ -z "$increment" ]; then
            increment=0
        fi
    fi
    
    # Return state
    if [ "$locked_value" = "1" ] || [ "$locked_value" = "true" ]; then
        echo "locked|$end_time|$increment"
    else
        echo "unlocked|0|$increment"
    fi
    return 0
}

# Get base duration and increment step from Abacus (with cache and hardcoded defaults)
get_config_from_abacus() {
    local base_duration=""
    local increment_step=""
    
    # Try to get from Abacus (check v2 keys first, then v1, then old format)
    base_duration=$(abacus_get "${PLACE_NAME}_base_duration_minutes_config_v2" 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$base_duration" ] || ! echo "$base_duration" | grep -qE '^[0-9]+$'; then
        base_duration=$(abacus_get "${PLACE_NAME}_base_duration_minutes_config" 2>/dev/null)
    fi
    if [ $? -ne 0 ] || [ -z "$base_duration" ] || ! echo "$base_duration" | grep -qE '^[0-9]+$'; then
        base_duration=$(abacus_get "${PLACE_NAME}_base_duration_minutes" 2>/dev/null)
    fi
    # Try cache if Abacus failed
    if [ -z "$base_duration" ] || ! echo "$base_duration" | grep -qE '^[0-9]+$'; then
        base_duration=$(cache_get "${PLACE_NAME}_base_duration_minutes_config_v2" 2>/dev/null || echo "")
        if [ -z "$base_duration" ] || ! echo "$base_duration" | grep -qE '^[0-9]+$'; then
            base_duration=$(cache_get "${PLACE_NAME}_base_duration_minutes_config" 2>/dev/null || echo "")
        fi
        if [ -z "$base_duration" ] || ! echo "$base_duration" | grep -qE '^[0-9]+$'; then
            base_duration=$(cache_get "${PLACE_NAME}_base_duration_minutes" 2>/dev/null || echo "")
        fi
    fi
    
    increment_step=$(abacus_get "${PLACE_NAME}_increment_step_seconds_config_v2" 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$increment_step" ] || ! echo "$increment_step" | grep -qE '^[0-9]+$'; then
        increment_step=$(abacus_get "${PLACE_NAME}_increment_step_seconds_config" 2>/dev/null)
    fi
    if [ $? -ne 0 ] || [ -z "$increment_step" ] || ! echo "$increment_step" | grep -qE '^[0-9]+$'; then
        increment_step=$(abacus_get "${PLACE_NAME}_increment_step_seconds" 2>/dev/null)
    fi
    # Try cache if Abacus failed
    if [ -z "$increment_step" ] || ! echo "$increment_step" | grep -qE '^[0-9]+$'; then
        increment_step=$(cache_get "${PLACE_NAME}_increment_step_seconds_config_v2" 2>/dev/null || echo "")
        if [ -z "$increment_step" ] || ! echo "$increment_step" | grep -qE '^[0-9]+$'; then
            increment_step=$(cache_get "${PLACE_NAME}_increment_step_seconds_config" 2>/dev/null || echo "")
        fi
        if [ -z "$increment_step" ] || ! echo "$increment_step" | grep -qE '^[0-9]+$'; then
            increment_step=$(cache_get "${PLACE_NAME}_increment_step_seconds" 2>/dev/null || echo "")
        fi
    fi
    
    # Use hardcoded defaults if Abacus unavailable and no cache
    # These are script defaults, NOT local cache
    if [ -z "$base_duration" ] || ! echo "$base_duration" | grep -qE '^[0-9]+$'; then
        base_duration=45  # Default 45 minutes
    fi
    if [ -z "$increment_step" ] || ! echo "$increment_step" | grep -qE '^[0-9]+$'; then
        increment_step=1  # Default 1 second
    fi
    
    echo "$base_duration|$increment_step"
    return 0
}

# Get current state from Abacus (with cache fallback)
STATE_INFO=$(get_state_from_abacus)
if [ $? -ne 0 ]; then
    # Abacus unavailable and no cache - FAIL
    echo "❌"  # Error emoji
    exit 1
fi

STATE=$(echo "$STATE_INFO" | cut -d'|' -f1)
END_TIME=$(echo "$STATE_INFO" | cut -d'|' -f2)
INCREMENT=$(echo "$STATE_INFO" | cut -d'|' -f3)

# Get config from Abacus (uses cache and hardcoded defaults if unavailable)
CONFIG_INFO=$(get_config_from_abacus)

BASE_DURATION_MINUTES=$(echo "$CONFIG_INFO" | cut -d'|' -f1)
INCREMENT_STEP_SECONDS=$(echo "$CONFIG_INFO" | cut -d'|' -f2)
BASE_LOCK=$((BASE_DURATION_MINUTES * 60))

if [ "$1" == "click-left" ] && [ "$STATE" == "unlocked" ]; then
    # Calculate lock duration: base + (increment * increment_step)
    LOCK_DURATION=$((BASE_LOCK + (INCREMENT * INCREMENT_STEP_SECONDS)))
    END_TIME=$(( $(date +%s) + LOCK_DURATION ))
    NEW_INCREMENT=$((INCREMENT + 1))
    
    # Write to Abacus immediately
    abacus_set "${PLACE_NAME}_is_locked" "1" || exit 1
    abacus_set "${PLACE_NAME}_lock_end_timestamp" "$((END_TIME * 1000))" || exit 1  # Convert to milliseconds
    abacus_set "${PLACE_NAME}_increment" "$NEW_INCREMENT" || exit 1
    abacus_track "${PLACE_NAME}_locks"
    
    # Update state
    STATE="locked"
fi

if [ "$1" == "click-middle" ]; then
    # Get fresh state from Abacus
    STATE_INFO=$(get_state_from_abacus)
    if [ $? -ne 0 ]; then
        notify-send "Smoke Timer" "Error: Cannot connect to Abacus"
        exit 1
    fi
    
    STATE=$(echo "$STATE_INFO" | cut -d'|' -f1)
    END_TIME=$(echo "$STATE_INFO" | cut -d'|' -f2)
    
    if [ "$STATE" == "locked" ] && [ "$END_TIME" != "0" ]; then
        NOW=$(date +%s)
        REM=$((END_TIME - NOW))
        if [ "$REM" -le 0 ]; then
            # Lock expired, unlock in Abacus
            abacus_set "${PLACE_NAME}_is_locked" "0" || exit 1
            abacus_set "${PLACE_NAME}_lock_end_timestamp" "0" || exit 1
            notify-send "Smoke Timer" "Unlocked! You can smoke now."
            STATE="unlocked"
        else
            HOURS=$((REM/3600))
            MIN=$(( (REM%3600)/60 ))
            SEC=$((REM%60))
            notify-send "Smoke Timer" "$HOURS h $MIN m $SEC s left"
        fi
    else
        notify-send "Smoke Timer" "Unlocked! You can smoke now."
    fi
fi

# Output emoji based on state from Abacus
if [ "$STATE" == "locked" ]; then
    echo 🌿
else
    echo 🚬
fi
