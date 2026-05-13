#!/usr/bin/env bash
set -u

state_file="${XDG_RUNTIME_DIR:-/tmp}/mbsync-hotmail-fail-state"
debounce_seconds=21600
maildir_root="$HOME/.local/share/mail/mvrozanti@hotmail.com"

auto_prune_vanished() {
    local input="$1"
    local still=""
    local box box_dir archive_dir file_count box_msgs archive_msgs unique
    while IFS= read -r box; do
        [ -z "$box" ] && continue
        box_dir="$maildir_root/$box"
        archive_dir="$maildir_root/Archive.$box"
        if [ ! -d "$box_dir" ]; then
            continue
        fi
        file_count=$(find "$box_dir/cur" "$box_dir/new" -type f 2>/dev/null | wc -l)
        if [ "$file_count" -eq 0 ]; then
            rm -rf "$box_dir"
            echo "auto-pruned empty orphan box: $box" >&2
            continue
        fi
        if [ ! -d "$archive_dir" ]; then
            still+="$box"$'\n'
            continue
        fi
        box_msgs=$(notmuch search --output=messages "folder:\"mvrozanti@hotmail.com/$box\"" 2>/dev/null | sort -u)
        archive_msgs=$(notmuch search --output=messages "folder:\"mvrozanti@hotmail.com/Archive.$box\"" 2>/dev/null | sort -u)
        if [ -z "$box_msgs" ]; then
            still+="$box"$'\n'
            continue
        fi
        unique=$(comm -23 <(echo "$box_msgs") <(echo "$archive_msgs"))
        if [ -z "$unique" ]; then
            local n
            n=$(echo "$box_msgs" | wc -l)
            rm -rf "$box_dir"
            echo "auto-pruned $box ($n msgs already in Archive.$box)" >&2
        else
            still+="$box"$'\n'
        fi
    done <<< "$input"
    printf '%s' "$still"
}

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
    if [ -n "$vanished" ]; then
        notmuch new --quiet >/dev/null 2>&1 || true
        vanished=$(auto_prune_vanished "$vanished")
    fi
    fingerprint=$(printf '%s' "$vanished" | sha256sum | cut -d' ' -f1)
    now=$(date +%s)
    should_notify=1
    if [ -z "$vanished" ]; then
        rm -f "$state_file"
        should_notify=0
    elif [ -f "$state_file" ]; then
        prev_ts=$(sed -n 1p "$state_file" 2>/dev/null || echo 0)
        prev_fp=$(sed -n 2p "$state_file" 2>/dev/null || echo "")
        if [ "$fingerprint" = "$prev_fp" ] && [ $(( now - prev_ts )) -lt "$debounce_seconds" ]; then
            should_notify=0
        fi
    fi
    if [ "$should_notify" -eq 1 ]; then
        body=$'IMAP boxes can no longer be opened on the server:\n'
        while IFS= read -r box; do
            [ -z "$box" ] && continue
            body+="  • $box"$'\n'
        done <<< "$vanished"
        body+=$'\nNot auto-prunable (no full duplicate under Archive.<name>). rm the matching local maildir under ~/.local/share/mail/mvrozanti@hotmail.com/ if intentional.'
        notify-send -u critical "Mail sync failed" "$body" || true
        printf '%s\n%s\n' "$now" "$fingerprint" > "$state_file"
    fi
fi

notmuch new --quiet || true

exit "$mbsync_status"
