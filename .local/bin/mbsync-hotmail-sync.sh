#!/usr/bin/env bash
set -u

mbsync_status=0
sync_output=$(mbsync mvrozanti@hotmail.com 2>&1) || mbsync_status=$?
echo "$sync_output"

if [ "$mbsync_status" -ne 0 ]; then
    notify-send -u critical "Mail sync failed" "mbsync exited $mbsync_status (check journalctl --user -u mbsync-hotmail)"
else
    slave_count=$(grep 'Inbox' -A6 <<< "$sync_output" | grep -E '^slave' | cut -d',' -f1 | tr -cd '[:digit:]' || echo 0)
    master_count=$(grep 'Inbox' -A6 <<< "$sync_output" | grep -E '^master' | cut -d',' -f1 | tr -cd '[:digit:]' || echo 0)
    new_mail_count=$(( ${master_count:-0} - ${slave_count:-0} ))
    if [ "$new_mail_count" -gt 0 ]; then
        notify-send "Mail" "You have $new_mail_count new email(s)."
    fi
fi

notmuch new --quiet || true

exit "$mbsync_status"
