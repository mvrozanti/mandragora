#!/usr/bin/env bash
set -u

sync_output=$(mbsync mvrozanti@hotmail.com 2>&1)
echo "$sync_output"

slave_count=$(grep 'Inbox' -A6 <<< "$sync_output" | grep -E '^slave' | cut -d',' -f1 | tr -cd '[:digit:]' || echo 0)
master_count=$(grep 'Inbox' -A6 <<< "$sync_output" | grep -E '^master' | cut -d',' -f1 | tr -cd '[:digit:]' || echo 0)

new_mail_count=$(( ${master_count:-0} - ${slave_count:-0} ))

if [ "$new_mail_count" -gt 0 ]; then
    notify-send "Mail" "You have $new_mail_count new email(s)."
fi
