#!/usr/bin/env bash
set -euo pipefail

POLL_SEC=10
COOLDOWN_SEC=300
MEM_AVAIL_PCT_THRESHOLD=15
SWAP_USED_PCT_THRESHOLD=70
LOG_DIR=/var/log/oom-tripwire
RETENTION_KEEP=50

mkdir -p "$LOG_DIR"

last_fire=0

while :; do
    now=$(date +%s)

    read -r mem_total mem_avail swap_total swap_free < <(
        awk '
            /^MemTotal:/  { mt = $2 }
            /^MemAvailable:/ { ma = $2 }
            /^SwapTotal:/ { st = $2 }
            /^SwapFree:/  { sf = $2 }
            END { print mt, ma, st, sf }
        ' /proc/meminfo
    )

    mem_avail_pct=$(( mem_avail * 100 / mem_total ))
    swap_used=$(( swap_total - swap_free ))
    swap_used_pct=0
    if (( swap_total > 0 )); then
        swap_used_pct=$(( swap_used * 100 / swap_total ))
    fi

    fire=0
    reason=""
    if (( mem_avail_pct < MEM_AVAIL_PCT_THRESHOLD )); then
        fire=1
        reason="MemAvailable ${mem_avail_pct}% < ${MEM_AVAIL_PCT_THRESHOLD}%"
    elif (( swap_used_pct > SWAP_USED_PCT_THRESHOLD )); then
        fire=1
        reason="SwapUsed ${swap_used_pct}% > ${SWAP_USED_PCT_THRESHOLD}%"
    fi

    if (( fire == 1 )) && (( now - last_fire >= COOLDOWN_SEC )); then
        last_fire=$now
        ts=$(date -u +%Y-%m-%dT%H-%M-%SZ)
        out="$LOG_DIR/$ts.log"

        {
            echo "=== oom-tripwire snapshot $ts ==="
            echo "trigger: $reason"
            echo "mem_total_kb=$mem_total mem_avail_kb=$mem_avail mem_avail_pct=$mem_avail_pct"
            echo "swap_total_kb=$swap_total swap_used_kb=$swap_used swap_used_pct=$swap_used_pct"
            echo
            echo "=== /proc/meminfo ==="
            cat /proc/meminfo
            echo
            echo "=== /proc/pressure/memory ==="
            cat /proc/pressure/memory 2>/dev/null || echo "(PSI unavailable)"
            echo
            echo "=== top 30 by RSS (ps auxf) ==="
            ps -eo pid,user,rss,vsz,pmem,pcpu,comm,args --sort=-rss | head -31
            echo
            echo "=== top 20 by swap (VmSwap) ==="
            for pid in /proc/[0-9]*; do
                p=${pid#/proc/}
                swap_kb=$(awk '/^VmSwap:/{print $2}' "$pid/status" 2>/dev/null || true)
                if [[ -n "${swap_kb:-}" ]] && (( swap_kb > 0 )); then
                    comm=$(cat "$pid/comm" 2>/dev/null || echo ?)
                    printf '%10d kB  pid=%s  comm=%s\n' "$swap_kb" "$p" "$comm"
                fi
            done | sort -nr | head -20
            echo
            echo "=== systemd-cgtop snapshot ==="
            systemd-cgtop --no-redirect -n 1 -b 2>/dev/null | head -30 || true
            echo
            echo "=== loginctl sessions ==="
            loginctl list-sessions --no-legend 2>&1
        } >"$out" 2>&1

        logger -t oom-tripwire -p user.warning "memory pressure: $reason — snapshot $out"

        ls -1t "$LOG_DIR"/*.log 2>/dev/null | tail -n +$((RETENTION_KEEP + 1)) | xargs -r rm -f
    fi

    sleep "$POLL_SEC"
done
