#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <search_string> <command_to_run> [args...]"
    exit 1
fi

search_string="$1"
shift
command_to_run=("$@")

echo "=== Waiting for processes with '$search_string' ==="
echo ""

while true; do
    matching_pids=()
    for pid_dir in /proc/[0-9]*/; do
        pid=$(basename "$pid_dir")
        [ "$pid" -eq $$ ] && continue
        if [ -f "/proc/$pid/cmdline" ]; then
            cmdline=$(cat "/proc/$pid/cmdline" 2>/dev/null | tr '\0' ' ')
            [ -z "$cmdline" ] && continue
            if [[ "$cmdline" == *"$search_string"* ]]; then
                [[ "$cmdline" == *"grep"*"$search_string"* ]] && continue
                [[ "$cmdline" == *"awk"*"$search_string"* ]] && continue
                [[ "$cmdline" == *"after"*"$search_string"* ]] && continue
                matching_pids+=("$pid")
            fi
        fi
    done

    if [ ${#matching_pids[@]} -eq 0 ]; then
        echo "No matching processes found."
        break
    fi

    echo "Found ${#matching_pids[@]} process(es):"
    for pid in "${matching_pids[@]}"; do
        if [ -f "/proc/$pid/cmdline" ]; then
            cmdline=$(cat "/proc/$pid/cmdline" 2>/dev/null | tr '\0' ' ')
            echo "  PID $pid: $(echo "$cmdline" | head -c 100)"
        fi
    done

    echo ""
    sleep 1
    echo ""
done

echo ""
echo "=== Running command ==="
"${command_to_run[@]}"
