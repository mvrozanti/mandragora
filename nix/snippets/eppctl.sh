#!/usr/bin/env bash
set -eu

EPP=/sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference
WAYBAR_SIGNAL=14

VALUES=(performance power)

current() {
  printf '%s' "$(<"$EPP")"
}

icon_for() {
  case "$1" in
    performance) printf '%s' $'' ;;
    power)       printf '%s' $'❄' ;;
    *)           printf '%s' $'' ;;
  esac
}

next_of() {
  local i n=${#VALUES[@]}
  for (( i = 0; i < n; i++ )); do
    if [[ "${VALUES[i]}" == "$1" ]]; then
      printf '%s' "${VALUES[$(( (i + 1) % n ))]}"
      return
    fi
  done
  printf '%s' "${VALUES[0]}"
}

write_all() {
  local f
  for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    echo "$1" > "$f" 2>/dev/null || { printf 'eppctl: cannot write %s (run via sudo)\n' "$1" >&2; return 1; }
  done
}

refresh() {
  pkill -SIGRTMIN+"$WAYBAR_SIGNAL" waybar 2>/dev/null || true
}

case "${1:-status}" in
  status)
    cur=$(current)
    printf '{"text": "%s", "tooltip": "CPU EPP: %s", "class": "%s"}\n' "$(icon_for "$cur")" "$cur" "$cur"
    ;;
  next)
    cur=$(current)
    nxt=$(next_of "$cur")
    write_all "$nxt" && refresh
    ;;
  set)
    val="${2:-}"
    case " ${VALUES[*]} " in
      *" $val "*) ;;
      *) printf 'eppctl: invalid value "%s" (use: %s)\n' "$val" "${VALUES[*]}" >&2; exit 1 ;;
    esac
    write_all "$val" && refresh
    ;;
  *)
    printf 'usage: eppctl [status|next|set <val>]\n' >&2
    exit 1
    ;;
esac
