#!/usr/bin/env bash
set -u

account="mvrozanti@hotmail.com"
maildir_root="$HOME/.local/share/mail/$account"
inbox_new_dir="$maildir_root/INBOX/new"
rescue_root="$HOME/.local/share/mail/orphaned/$account"
backoff_file="${XDG_RUNTIME_DIR:-/tmp}/mbsync-hotmail-backoff"
base_delay=300
max_delay=3600
page_threshold=3

list_unseen_inbox() {
    { find "$inbox_new_dir" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null || true; } | sort
}

retire_vanished_box() {
    local box="$1"
    local dir_name="${box//\//.}"
    local box_dir="$maildir_root/$dir_name"
    local rescue_dir="$rescue_root/$dir_name"
    local query="folder:\"$account/${dir_name//\"/\"\"}\""
    local -A elsewhere=()
    local listing file other sub rescued=0 dropped=0
    local -a row
    [ -d "$box_dir" ] || return 0
    notmuch new --quiet >/dev/null 2>&1 || true
    if ! listing=$(notmuch show --format=json --entire-thread=false --body=false "$query" \
        | jq -r --arg dir "$box_dir/" '
            .. | objects | select(has("filename") and .match == true)
            | .filename as $f
            | ($f | map(select(startswith($dir) | not))) as $out
            | $f[] | select(startswith($dir)) | [.] + $out | @tsv'); then
        echo "vanished box $box: notmuch lookup failed, left in place" >&2
        return 0
    fi
    while IFS=$'\t' read -r -a row; do
        [ "${#row[@]}" -gt 1 ] || continue
        for other in "${row[@]:1}"; do
            if [ -e "$other" ]; then
                elsewhere["${row[0]}"]=1
                break
            fi
        done
    done <<< "$listing"
    for sub in cur new tmp; do
        [ -d "$box_dir/$sub" ] || continue
        while IFS= read -r -d '' file; do
            if [ -n "${elsewhere[$file]:-}" ]; then
                dropped=$((dropped + 1))
                continue
            fi
            mkdir -p "$rescue_dir/cur" "$rescue_dir/new" "$rescue_dir/tmp"
            if ! mv --update=none-fail -- "$file" "$rescue_dir/$sub/"; then
                echo "vanished box $box: could not move $file aside, left in place" >&2
                return 0
            fi
            rescued=$((rescued + 1))
        done < <(find "$box_dir/$sub" -maxdepth 1 -type f -print0)
    done
    rm -rf -- "$box_dir"
    echo "retired vanished box $box: $dropped already elsewhere, $rescued kept in $rescue_dir"
    if [ "$rescued" -gt 0 ]; then
        notify-send "Mail folder removed on the server" \
            "$box: $rescued message(s) had no other copy and were kept in $rescue_dir" || true
    fi
}

if mail-menu needs-auth; then
    echo "mbsync result=needs-auth"
    exit 0
fi

consecutive=0
next_attempt=0
if [ -f "$backoff_file" ]; then
    consecutive=$(sed -n 1p "$backoff_file" 2>/dev/null || echo 0)
    next_attempt=$(sed -n 2p "$backoff_file" 2>/dev/null || echo 0)
fi
now=$(date +%s)
if [ "$now" -lt "$next_attempt" ]; then
    echo "mbsync result=backoff consecutive=$consecutive delay_seconds=$((next_attempt - now))"
    if [ "$consecutive" -lt "$page_threshold" ]; then
        exit 0
    fi
    exit 1
fi

unseen_before=$(list_unseen_inbox)
mbsync_status=0
sync_output=$(mbsync mvrozanti@hotmail.com 2>&1) || mbsync_status=$?
echo "$sync_output"

if [ "$mbsync_status" -eq 0 ]; then
    rm -f "$backoff_file"
    echo "mbsync result=success consecutive=0"
    mail-menu mark-synced || true
    new_mail_count=$(comm -13 <(printf '%s\n' "$unseen_before") <(list_unseen_inbox) | grep -c . || true)
    echo "mbsync new_inbox_mail=$new_mail_count"
    if [ "$new_mail_count" -gt 0 ]; then
        notify-send "Mail" "You have $new_mail_count new email(s)." || true
    fi
    mapfile -t vanished < <(sed -n 's/^Warning: channel [^:]*: far side box \(.*\) cannot be opened anymore, and near side box .* is not empty\.$/\1/p' <<< "$sync_output" | sort -u)
    for box in "${vanished[@]}"; do
        [ -n "$box" ] && retire_vanished_box "$box"
    done
elif grep -q 'PassCmd exited' <<< "$sync_output"; then
    rm -f "$backoff_file"
    echo "mbsync result=needs-auth"
    mail-menu mark-needs-auth || true
    exit 0
else
    now=$(date +%s)
    consecutive=$((consecutive + 1))
    exponent=$((consecutive - 1))
    [ "$exponent" -gt 8 ] && exponent=8
    delay=$((base_delay * 2 ** exponent))
    if [ "$delay" -gt "$max_delay" ]; then
        delay=$max_delay
    fi
    printf '%s\n%s\n' "$consecutive" "$((now + delay))" > "$backoff_file"
    echo "mbsync result=failure consecutive=$consecutive delay_seconds=$delay"
fi

notmuch new --quiet || true

if [ "$mbsync_status" -ne 0 ] && [ "$consecutive" -lt "$page_threshold" ]; then
    exit 0
fi
exit "$mbsync_status"
