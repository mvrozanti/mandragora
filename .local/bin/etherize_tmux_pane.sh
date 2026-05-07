#!/usr/bin/env bash
set -eu

pane=${1:-${TMUX_PANE:-}}
[[ -n $pane ]] || exit 1

pid=$(tmux display -pt "$pane" '#{pane_pid}')
tty=$(tmux display -pt "$pane" '#{pane_tty}')
target=$(ps -t "$tty" -o tpgid= 2>/dev/null | sort -u | tail -1 | tr -d ' ')
[[ -n $target && $target != -1 ]] || target=$pid

setsid -f script -qc "reptyr $target" /dev/null </dev/null >/dev/null 2>&1

expect=$(( (0x$(stat -c '%t' "$tty") << 8) | 0x$(stat -c '%T' "$tty") ))
for _ in $(seq 1 30); do
    cur=$(awk '{print $7}' "/proc/$target/stat" 2>/dev/null || true)
    [[ -n $cur && $cur != "$expect" ]] && { tmux kill-pane -t "$pane"; exit 0; }
    sleep 0.05
done

tmux display -t "$pane" "ether: reptyr didn't take over"
exit 1
