#!/usr/bin/env bash
pattern="$1"
shift
[ "$#" -gt 0 ] || exit 2
name=$(basename -- "${!#}")

matching() {
    hyprctl clients -j | jq -r --arg re "$pattern" --arg name "$name" \
        '.[] | select(.class | test($re; "i")) | [.address, (.title | startswith($name) | tostring)] | @tsv'
}

before=$(matching | cut -f1 | sort)
hyprctl dispatch exec "$(printf '%q ' "$@")" >/dev/null

for i in $(seq 1 100); do
    sleep 0.2
    now=$(matching)
    addr=$(comm -13 <(printf '%s\n' "$before") <(cut -f1 <<<"$now" | sort) | head -1)
    if [ -z "$addr" ] && [ "$i" -ge 10 ]; then
        addr=$(awk -F'\t' '$2 == "true" { print $1; exit }' <<<"$now")
    fi
    if [ -n "$addr" ]; then
        hyprctl dispatch focuswindow "address:$addr" >/dev/null
        exit 0
    fi
done
