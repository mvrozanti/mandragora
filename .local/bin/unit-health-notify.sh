#!/usr/bin/env bash
set -uo pipefail

mode="${1:-}"
unit="${2:-}"
[ -n "$mode" ] && [ -n "$unit" ] || exit 0

if [ "$EUID" -eq 0 ]; then
  dir="@systemDir@"
  scope=(--system)
else
  dir="${XDG_STATE_HOME:-$HOME/.local/state}/unit-health"
  scope=(--user)
fi
mkdir -p "$dir"

host="$(cat /proc/sys/kernel/hostname)"
now="$(date +%s)"

human() {
  local s=$1
  if [ "$s" -ge 86400 ]; then
    printf '%dd %dh' $((s / 86400)) $((s % 86400 / 3600))
  elif [ "$s" -ge 3600 ]; then
    printf '%dh %dmin' $((s / 3600)) $((s % 3600 / 60))
  else
    printf '%dmin' $((s / 60))
  fi
}

failed() {
  declare -A p=()
  local k v
  while IFS='=' read -r k v; do
    p[$k]="$v"
  done < <(systemctl "${scope[@]}" show "$unit" \
    -p Type -p TriggeredBy -p Result -p ExecMainStatus -p InvocationID)

  local trig="${p[TriggeredBy]:-}"
  if [ "${p[Type]:-}" != oneshot ] && [[ $trig != *.timer* && $trig != *.path* ]]; then
    exit 0
  fi

  local f="$dir/$unit.failing" since count rest
  if [ -e "$f" ]; then
    read -r since count rest < "$f" || true
    printf '%s %s %s\n' "${since:-$now}" $((${count:-0} + 1)) "$now" > "$f"
    exit 0
  fi
  printf '%s 1 %s\n' "$now" "$now" > "$f"

  local tail=""
  if [ -n "${p[InvocationID]:-}" ]; then
    tail="$(journalctl "${scope[@]}" -u "$unit" --invocation="${p[InvocationID]}" \
      -o cat --no-pager 2>/dev/null \
      | grep -v -e "^$unit: " -e '^Failed to start ' -e '^Starting ' \
      | tail -n 10 | cut -c1-300)"
  fi

  local where=""
  [ "${scope[0]}" = --user ] && where=" --user"
  local msg
  msg="FAILED on $host: $unit (${p[Result]:-unknown}, exit ${p[ExecMainStatus]:-?})"
  [ -n "$tail" ] && msg+=$'\n\n'"$tail"
  msg+=$'\n\n'"Quiet until it succeeds again. systemctl$where status $unit"
  telegram-notify "$msg"
}

recovered() {
  local f="$dir/$unit.recovered" since count rest
  [ -e "$f" ] || exit 0
  read -r since count rest < "$f" || true
  rm -f "$f"
  local dur=$((now - ${since:-$now}))
  telegram-notify "RECOVERED on $host: $unit succeeded after $(human "$dur") failing (${count:-?} failed runs)"
}

case "$mode" in
  failed) failed ;;
  recovered) recovered ;;
  *) echo "unknown mode $mode" >&2; exit 2 ;;
esac
