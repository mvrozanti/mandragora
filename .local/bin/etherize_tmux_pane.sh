#!/usr/bin/env bash
exec >/dev/null 2>&1

pane=${1:-${TMUX_PANE:-}}
[[ -n $pane ]] || exit 0

pid=$(tmux display -pt "$pane" '#{pane_pid}')
tty=$(tmux display -pt "$pane" '#{pane_tty}')
target=$(ps -t "$tty" -o tpgid= | sort -u | tail -1 | tr -d ' ')
[[ -n $target && $target != -1 ]] || target=$pid

setsid -f script -qc "reptyr $target" /dev/null </dev/null

expect=$(( (0x$(stat -c '%t' "$tty") << 8) | 0x$(stat -c '%T' "$tty") ))
for _ in $(seq 1 60); do
    cur=$(awk '{print $7}' "/proc/$target/stat")
    [[ -n $cur && $cur != "$expect" ]] && break
    sleep 0.05
done

tmux kill-pane -t "$pane"
exit 0
