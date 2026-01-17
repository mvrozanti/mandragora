#!/usr/bin/env bash

# Configuration
ABACUS_BASE_URL="https://abacus.jasoncameron.dev"
ABACUS_NAMESPACE="airtime"
PLACE_ID="default"  # Use "default" or set SMOKE_PLACE_ID env var

# Local state files (used as cache/fallback)
STATE_FILE="/tmp/smoke_timer.state"
END_FILE="/tmp/smoke_timer.end"
INCREMENT_FILE="/tmp/smoke_timer.increment"

# Base lock duration (45 minutes in seconds)
BASE_LOCK=$((45*60))

# Abacus API helper functions
abacus_get() {
    local key="$1"
    local url="${ABACUS_BASE_URL}/get/${ABACUS_NAMESPACE}/${key}"
    local value=$(curl -s --connect-timeout 5 --max-time 5 "$url" 2>/dev/null)
    if [ -n "$value" ] && [ "$value" != "null" ]; then
        echo "$value"
    else
        echo ""
    fi
}

abacus_set() {
    local key="$1"
    local value="$2"
    local url="${ABACUS_BASE_URL}/set/${ABACUS_NAMESPACE}/${key}/${value}"
    curl -s --connect-timeout 5 --max-time 5 -X POST "$url" >/dev/null 2>&1
}

abacus_track() {
    local key="$1"
    local url="${ABACUS_BASE_URL}/hit/${ABACUS_NAMESPACE}/${key}"
    curl -s --connect-timeout 5 --max-time 5 "$url" >/dev/null 2>&1
}

# Sync state from Abacus to local files
sync_from_abacus() {
    # Get lock state (stored as is_locked in Android, we'll use a key for bash)
    local locked_value=$(abacus_get "${PLACE_ID}_is_locked")
    if [ -n "$locked_value" ]; then
        if [ "$locked_value" = "1" ] || [ "$locked_value" = "true" ]; then
            echo "locked" > "$STATE_FILE"
        else
            echo "unlocked" > "$STATE_FILE"
        fi
    fi
    
    # Get lock end timestamp
    local end_time=$(abacus_get "${PLACE_ID}_lock_end_timestamp")
    if [ -n "$end_time" ] && [ "$end_time" != "0" ]; then
        echo "$end_time" > "$END_FILE"
    fi
    
    # Get increment
    local increment=$(abacus_get "${PLACE_ID}_increment")
    if [ -n "$increment" ]; then
        echo "$increment" > "$INCREMENT_FILE"
    fi
}

# Sync state from local files to Abacus
sync_to_abacus() {
    if [ -f "$STATE_FILE" ]; then
        local state=$(cat "$STATE_FILE")
        if [ "$state" = "locked" ]; then
            abacus_set "${PLACE_ID}_is_locked" "1"
        else
            abacus_set "${PLACE_ID}_is_locked" "0"
        fi
    fi
    
    if [ -f "$END_FILE" ]; then
        local end_time=$(cat "$END_FILE")
        abacus_set "${PLACE_ID}_lock_end_timestamp" "$end_time"
    fi
    
    if [ -f "$INCREMENT_FILE" ]; then
        local increment=$(cat "$INCREMENT_FILE")
        abacus_set "${PLACE_ID}_increment" "$increment"
    fi
}

# Initialize local files if they don't exist
if [ ! -f "$STATE_FILE" ]; then
    echo "unlocked" > "$STATE_FILE"
fi
if [ ! -f "$INCREMENT_FILE" ]; then
    echo 0 > "$INCREMENT_FILE"
fi

# Try to sync from Abacus on startup (but don't fail if API is down)
sync_from_abacus 2>/dev/null || true

# Read current state (from local cache)
STATE=$(cat "$STATE_FILE")
INCREMENT=$(cat "$INCREMENT_FILE" 2>/dev/null || echo "0")

# Try to get base duration and increment step from Abacus (with fallback)
BASE_DURATION_MINUTES=$(abacus_get "${PLACE_ID}_base_duration_minutes" 2>/dev/null || echo "")
if [ -z "$BASE_DURATION_MINUTES" ]; then
    BASE_DURATION_MINUTES=45
fi
BASE_LOCK=$((BASE_DURATION_MINUTES * 60))

INCREMENT_STEP_SECONDS=$(abacus_get "${PLACE_ID}_increment_step_seconds" 2>/dev/null || echo "")
if [ -z "$INCREMENT_STEP_SECONDS" ]; then
    INCREMENT_STEP_SECONDS=1
fi

if [ "$1" == "click-left" ] && [ "$STATE" == "unlocked" ]; then
    # Calculate lock duration: base + (increment * increment_step)
    LOCK_DURATION=$((BASE_LOCK + (INCREMENT * INCREMENT_STEP_SECONDS)))
    echo "locked" > "$STATE_FILE"
    END_TIME=$(( $(date +%s) + LOCK_DURATION ))
    echo "$END_TIME" > "$END_FILE"
    INCREMENT=$((INCREMENT + 1))
    echo "$INCREMENT" > "$INCREMENT_FILE"
    
    # Sync to Abacus
    sync_to_abacus
    abacus_track "${PLACE_ID}_locks"
    
    # Start background unlock process
    (sleep $LOCK_DURATION && echo "unlocked" > "$STATE_FILE" && rm -f "$END_FILE" && sync_to_abacus) &
fi

# Re-read state after potential lock
STATE=$(cat "$STATE_FILE")

if [ "$1" == "click-middle" ]; then
    # Sync from Abacus first to get latest state
    sync_from_abacus 2>/dev/null || true
    STATE=$(cat "$STATE_FILE")
    
    if [ -f "$END_FILE" ]; then
        END_TIME=$(cat "$END_FILE")
        NOW=$(date +%s)
        REM=$((END_TIME - NOW))
        if [ "$REM" -le 0 ]; then
            echo "unlocked" > "$STATE_FILE"
            rm -f "$END_FILE"
            sync_to_abacus
            notify-send "Smoke Timer" "Unlocked! You can smoke now."
        else
            HOURS=$((REM/3600))
            MIN=$(( (REM%3600)/60 ))
            SEC=$((REM%60))
            notify-send "Smoke Timer" "$HOURS h $MIN m $SEC s left"
        fi
    else
        # Check Abacus for end time
        END_TIME=$(abacus_get "${PLACE_ID}_lock_end_timestamp" 2>/dev/null || echo "0")
        if [ -n "$END_TIME" ] && [ "$END_TIME" != "0" ]; then
            NOW=$(date +%s)
            REM=$((END_TIME - NOW))
            if [ "$REM" -le 0 ]; then
                echo "unlocked" > "$STATE_FILE"
                sync_to_abacus
                notify-send "Smoke Timer" "Unlocked! You can smoke now."
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
fi

# Sync state to Abacus periodically (every time script runs)
sync_to_abacus 2>/dev/null || true

# Output emoji based on state
if [ "$STATE" == "locked" ]; then
    echo 🌿
else
    echo 🚬
fi
