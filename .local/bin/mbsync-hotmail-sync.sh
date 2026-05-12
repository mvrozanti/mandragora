#!/usr/bin/env bash
set -u

state_file="${XDG_RUNTIME_DIR:-/tmp}/mbsync-hotmail-fail-state"
debounce_seconds=21600

mbsync_status=0
sync_output=$(mbsync mvrozanti@hotmail.com 2>&1) || mbsync_status=$?
echo "$sync_output"

if [ "$mbsync_status" -eq 0 ]; then
    rm -f "$state_file"
    slave_count=$(grep 'Inbox' -A6 <<< "$sync_output" | grep -E '^slave' | cut -d',' -f1 | tr -cd '[:digit:]' || echo 0)
    master_count=$(grep 'Inbox' -A6 <<< "$sync_output" | grep -E '^master' | cut -d',' -f1 | tr -cd '[:digit:]' || echo 0)
    new_mail_count=$(( ${master_count:-0} - ${slave_count:-0} ))
    if [ "$new_mail_count" -gt 0 ]; then
        notify-send "Mail" "You have $new_mail_count new email(s)." || true
    fi
else
    vanished=$(sed -n 's/^Error: channel [^:]*: far side box \(.*\) cannot be opened anymore\.$/\1/p' <<< "$sync_output" | sort -u)
    fingerprint=$(printf '%s' "$vanished" | sha256sum | cut -d' ' -f1)
    now=$(date +%s)
    should_notify=1
    if [ -f "$state_file" ]; then
        prev_ts=$(sed -n 1p "$state_file" 2>/dev/null || echo 0)
        prev_fp=$(sed -n 2p "$state_file" 2>/dev/null || echo "")
        if [ "$fingerprint" = "$prev_fp" ] && [ $(( now - prev_ts )) -lt "$debounce_seconds" ]; then
            should_notify=0
        fi
    fi
    if [ "$should_notify" -eq 1 ]; then
        if [ -n "$vanished" ]; then
            body=$'IMAP boxes can no longer be opened on the server:\n'
            while IFS= read -r box; do
                body+="  • $box"$'\n'
            done <<< "$vanished"
            body+=$'\nIf intentional, rm the matching local maildir under ~/.local/share/mail/mvrozanti@hotmail.com/'
            notify-send -u critical "Mail sync failed" "$body" || true
        else
            notify-send -u critical "Mail sync failed" "mbsync exited $mbsync_status. Run: journalctl --user -u mbsync-hotmail" || true
        fi
        printf '%s\n%s\n' "$now" "$fingerprint" > "$state_file"
    fi
fi

notmuch new --quiet || true

exit "$mbsync_status"
