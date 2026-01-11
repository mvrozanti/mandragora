#!/usr/bin/env bash

STATE_FILE="/tmp/smoke_timer.state"
END_FILE="/tmp/smoke_timer.end"
INCREMENT_FILE="/tmp/smoke_timer.increment"

BASE_LOCK=$((45*60))

if [ ! -f "$STATE_FILE" ]; then
    echo "unlocked" > "$STATE_FILE"
fi
if [ ! -f "$INCREMENT_FILE" ]; then
    echo 0 > "$INCREMENT_FILE"
fi

STATE=$(cat "$STATE_FILE")
INCREMENT=$(cat "$INCREMENT_FILE")

if [ "$1" == "click-left" ] && [ "$STATE" == "unlocked" ]; then
    LOCK_DURATION=$((BASE_LOCK + INCREMENT))
    echo "locked" > "$STATE_FILE"
    END_TIME=$(( $(date +%s) + LOCK_DURATION ))
    echo "$END_TIME" > "$END_FILE"
    INCREMENT=$((INCREMENT + 1))
    echo "$INCREMENT" > "$INCREMENT_FILE"
    (sleep $LOCK_DURATION && echo "unlocked" > "$STATE_FILE" && rm -f "$END_FILE") &
fi

STATE=$(cat "$STATE_FILE")

if [ "$1" == "click-middle" ]; then
    if [ -f "$END_FILE" ]; then
        END_TIME=$(cat "$END_FILE")
        NOW=$(date +%s)
        REM=$((END_TIME - NOW))
        if [ "$REM" -le 0 ]; then
            echo "unlocked" > "$STATE_FILE"
            rm -f "$END_FILE"
            notify-send "Smoke Timer" "Unlocked! You can smoke now."
        else
            HOURS=$((REM/3600))
            MIN=$(( (REM%3600)/60 ))
            SEC=$((REM%60))
            notify-send "Smoke Timer" "Next smoke in: $HOURS h $MIN m $SEC s"
        fi
    else
        notify-send "Smoke Timer" "Unlocked! You can smoke now."
    fi
fi

if [ "$STATE" == "locked" ]; then
    echo 🌿
else
    echo 🚬
fi
