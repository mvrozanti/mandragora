#!/usr/bin/env bash
set -eu

pane_id="${1:-${TMUX_PANE:-}}"
if [[ -z "$pane_id" ]]; then
    echo "etherize: not in a tmux pane" >&2
    exit 1
fi

pane_pid=$(tmux display-message -p -t "$pane_id" '#{pane_pid}')
pane_tty=$(tmux display-message -p -t "$pane_id" '#{pane_tty}')

fg_pgid=$(ps -t "$pane_tty" -o tpgid= 2>/dev/null | sort -u | tail -1 | tr -d ' ')
if [[ -z "$fg_pgid" || "$fg_pgid" == "-1" ]]; then
    tmux display-message -t "$pane_id" "ether: no foreground process group on pane tty"
    exit 0
fi

target=$fg_pgid
if ! [[ -d /proc/$target ]]; then
    tmux display-message -t "$pane_id" "ether: target $target not found"
    exit 0
fi

ether_dir="${XDG_RUNTIME_DIR:-/run/user/$UID}/tmux-ether"
mkdir -p "$ether_dir"
sock=$(mktemp -u "$ether_dir/sock-XXXXXX")
log=$(mktemp "$ether_dir/log-XXXXXX")

reptyr_bin=/run/wrappers/bin/reptyr
[[ -x "$reptyr_bin" ]] || reptyr_bin=$(command -v reptyr)

setsid -f dtach -n "$sock" -E "$reptyr_bin" "$target" >"$log" 2>&1 || true

expected_tty=$(( (0x$(stat -c '%t' "$pane_tty") << 8) | 0x$(stat -c '%T' "$pane_tty") ))
ok=0
for _ in $(seq 1 80); do
    if ! [[ -d /proc/$target ]]; then
        break
    fi
    cur=$(awk '{print $7}' "/proc/$target/stat" 2>/dev/null || true)
    if [[ -n "$cur" && "$cur" != "$expected_tty" ]]; then
        ok=1
        break
    fi
    sleep 0.05
done

if [[ $ok -ne 1 ]]; then
    tmux display-message -t "$pane_id" "ether: reptyr stalled (log: $log)"
    exit 1
fi

tmux display-message -t "$pane_id" "etherized $target → $sock"

kill -KILL "$pane_pid" 2>/dev/null || true
