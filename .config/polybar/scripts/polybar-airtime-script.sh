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
    local http_code
    local response
    local admin_key
    
    # Get HTTP status code and response
    response=$(curl -s -w "\n%{http_code}" --connect-timeout 5 --max-time 5 -X POST "$url" 2>/dev/null)
    http_code=$(echo "$response" | tail -n1)
    response=$(echo "$response" | sed '$d')
    
    # If counter already exists (409), we can't get admin key this way
    if [ "$http_code" = "409" ]; then
        echo "Counter ${key} already exists but no admin key available" >&2
        return 1
    fi
    
    # Check if response contains an admin key
    if [ -n "$response" ]; then
        # Try to extract admin key from JSON or use as-is
        admin_key=$(echo "$response" | grep -oE '"admin_key"\s*:\s*"[^"]+"' | grep -oE '"[^"]+"' | tr -d '"')
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
        admin_key=$(abacus_create "$key" 2>&1)
        if [ -n "$admin_key" ] && [ "${admin_key:0:7}" != "Counter" ]; then
            # Got valid admin key (not an error message)
            abacus_store_admin_key "$key" "$admin_key"
        else
            # Can't write without admin key - log error
            echo "ERROR: Cannot set ${key}: Counter exists but no admin key available. Use Android app to lock first." >&2
            return 1
        fi
    fi
    
    # Use admin key to write
    local http_code
    local response
    response=$(curl -s -w "\n%{http_code}" --connect-timeout 5 --max-time 5 -X POST \
        -H "Authorization: Bearer ${admin_key}" \
        "$url" 2>/dev/null)
    http_code=$(echo "$response" | tail -n1)
    response=$(echo "$response" | sed '$d')
    
    # Check if we got a 401 (invalid token) - clear admin key and retry
    if [ "$http_code" = "401" ] || echo "$response" | grep -q "invalid\|token"; then
        # Clear stored admin key
        grep -v "^${key}=" "$ADMIN_KEYS_FILE" > "${ADMIN_KEYS_FILE}.tmp" 2>/dev/null || true
        mv "${ADMIN_KEYS_FILE}.tmp" "$ADMIN_KEYS_FILE" 2>/dev/null || true
        # Try to recreate
        admin_key=$(abacus_create "$key" 2>&1)
        if [ -n "$admin_key" ] && [ "${admin_key:0:7}" != "Counter" ]; then
            abacus_store_admin_key "$key" "$admin_key"
            # Retry with new key
            response=$(curl -s -w "\n%{http_code}" --connect-timeout 5 --max-time 5 -X POST \
                -H "Authorization: Bearer ${admin_key}" \
                "$url" 2>/dev/null)
            http_code=$(echo "$response" | tail -n1)
        else
            echo "ERROR: Cannot set ${key}: Invalid admin key and cannot recreate" >&2
            return 1
        fi
    fi
    
    # Check if successful (2xx HTTP status)
    if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
        cache_set "$key" "$value"
        return 0
    fi
    
    echo "ERROR: Failed to set ${key}: HTTP ${http_code}" >&2
    return 1
}

abacus_track() {
    local key="$1"
    local url="${ABACUS_BASE_URL}/hit/${ABACUS_NAMESPACE}/${key}"
    curl -s --connect-timeout 5 --max-time 5 "$url" >/dev/null 2>&1
}

# Convert timestamp to seconds (handles both ms and s)
to_seconds() {
    local ts="$1"
    if [ -z "$ts" ] || [ "$ts" = "0" ]; then
        echo "0"
    elif [ "$ts" -gt 10000000000 ] 2>/dev/null; then
        # Milliseconds - convert to seconds
        echo "$((ts / 1000))"
    else
        # Already in seconds
        echo "$ts"
    fi
}

# Get current state directly from Abacus (with cache fallback)
get_state_from_abacus() {
    local lock_sequence=""
    local end_time_raw=""
    local end_time=""
    local increment=""
    local old_locked=""
    local state=""
    
    # Get lock sequence from Abacus - source of truth (increment-only counter)
    # Odd = locked, even = unlocked
    lock_sequence=$(abacus_get "${PLACE_NAME}_lock_sequence" 2>/dev/null)
    
    # Check if we got a valid numeric value
    if [ -z "$lock_sequence" ] || ! echo "$lock_sequence" | grep -qE '^[0-9]+$'; then
        # Abacus unavailable or key not found - try cache
        lock_sequence=$(cache_get "${PLACE_NAME}_lock_sequence" 2>/dev/null)
        
        if [ -z "$lock_sequence" ] || ! echo "$lock_sequence" | grep -qE '^[0-9]+$'; then
            # No cache either - try backward compatibility with old is_locked key
            old_locked=$(abacus_get "${PLACE_NAME}_is_locked" 2>/dev/null)
            
            if [ -n "$old_locked" ] && echo "$old_locked" | grep -qE '^[01]$'; then
                # Old key exists - convert to lock_sequence format (1 = locked = odd, 0 = unlocked = even)
                if [ "$old_locked" = "1" ]; then
                    lock_sequence="1"  # Odd = locked
                else
                    lock_sequence="0"  # Even = unlocked
                fi
            else
                # No old key either - default to unlocked (0 = even = unlocked)
                lock_sequence="0"
            fi
        fi
    fi
    
    # Get lock end timestamp from Abacus (stored in MILLISECONDS, return in SECONDS)
    end_time_raw=$(abacus_get "${PLACE_NAME}_lock_end_timestamp" 2>/dev/null)
    
    if [ -z "$end_time_raw" ] || [ "$end_time_raw" = "0" ] || ! echo "$end_time_raw" | grep -qE '^[0-9]+$'; then
        # Try cache
        end_time_raw=$(cache_get "${PLACE_NAME}_lock_end_timestamp" 2>/dev/null)
        if [ -z "$end_time_raw" ]; then
            end_time_raw="0"
        fi
    fi
    end_time=$(to_seconds "$end_time_raw")
    
    # Get increment from Abacus
    increment=$(abacus_get "${PLACE_NAME}_increment" 2>/dev/null)
    
    if [ -z "$increment" ] || ! echo "$increment" | grep -qE '^[0-9]+$'; then
        # Try cache
        increment=$(cache_get "${PLACE_NAME}_increment" 2>/dev/null)
        if [ -z "$increment" ] || ! echo "$increment" | grep -qE '^[0-9]+$'; then
            increment="0"
        fi
    fi
    
    # Determine state from lock_sequence: odd = locked, even = unlocked
    # Ensure lock_sequence is numeric (default to 0 if not)
    if ! echo "$lock_sequence" | grep -qE '^[0-9]+$'; then
        lock_sequence="0"
    fi
    
    if [ $((lock_sequence % 2)) -eq 1 ]; then
        state="locked"
    else
        state="unlocked"
    fi
    
    # Return state (end_time is in SECONDS)
    if [ "$state" = "locked" ]; then
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
    END_TIME_SEC=$(( $(date +%s) + LOCK_DURATION ))  # In SECONDS
    NEW_INCREMENT=$((INCREMENT + 1))
    
    # Increment lock_sequence (no admin key needed!) - odd = locked
    # Clear cache first so we get fresh value after increment
    rm -f "${CACHE_DIR}/${PLACE_NAME}_lock_sequence" 2>/dev/null || true
    abacus_track "${PLACE_NAME}_lock_sequence"
    
    # Invalidate cache so next read gets fresh value
    rm -f "${CACHE_DIR}/${PLACE_NAME}_lock_sequence" 2>/dev/null || true
    
    # Store lock_end_timestamp in MILLISECONDS (to match Android app)
    abacus_set "${PLACE_NAME}_lock_end_timestamp" "$((END_TIME_SEC * 1000))" 2>/dev/null || true
    
    # Also update increment if we have admin key (optional)
    abacus_set "${PLACE_NAME}_increment" "$NEW_INCREMENT" 2>/dev/null || true
    
    abacus_track "${PLACE_NAME}_locks"
    
    # Update state (lock_sequence is now odd, so locked)
    STATE="locked"
    END_TIME="$END_TIME_SEC"  # Keep in seconds for display
fi

if [ "$1" == "click-middle" ]; then
    # Get fresh state from Abacus
    STATE_INFO=$(get_state_from_abacus)
    if [ $? -ne 0 ]; then
        notify-send "Smoke Timer" "Error: Cannot connect to Abacus"
        exit 1
    fi
    
    STATE=$(echo "$STATE_INFO" | cut -d'|' -f1)
    END_TIME_SEC=$(echo "$STATE_INFO" | cut -d'|' -f2)  # Already in SECONDS from get_state_from_abacus
    INCREMENT=$(echo "$STATE_INFO" | cut -d'|' -f3)
    
    if [ "$STATE" == "locked" ]; then
        # If END_TIME_SEC is 0 or missing, calculate it from config
        if [ "$END_TIME_SEC" = "0" ] || [ -z "$END_TIME_SEC" ]; then
            # Calculate default lock duration
            CONFIG_INFO=$(get_config_from_abacus)
            BASE_DURATION_MINUTES=$(echo "$CONFIG_INFO" | cut -d'|' -f1)
            INCREMENT_STEP_SECONDS=$(echo "$CONFIG_INFO" | cut -d'|' -f2)
            BASE_LOCK=$((BASE_DURATION_MINUTES * 60))
            LOCK_DURATION=$((BASE_LOCK + (INCREMENT * INCREMENT_STEP_SECONDS)))
            END_TIME_SEC=$(( $(date +%s) + LOCK_DURATION ))
        fi
        
        NOW=$(date +%s)
        REM=$((END_TIME_SEC - NOW))
        if [ "$REM" -le 0 ]; then
            # Lock expired, unlock in Abacus by incrementing lock_sequence to make it even
            rm -f "${CACHE_DIR}/${PLACE_NAME}_lock_sequence" 2>/dev/null || true
            abacus_track "${PLACE_NAME}_lock_sequence"
            rm -f "${CACHE_DIR}/${PLACE_NAME}_lock_sequence" 2>/dev/null || true
            abacus_set "${PLACE_NAME}_lock_end_timestamp" "0" 2>/dev/null || true
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
