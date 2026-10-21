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

loop_window=600
loop_threshold=5
loop_repeat=3600

journal_tail() {
  [ -n "${p[InvocationID]:-}" ] || return 0
  journalctl "${scope[@]}" -u "$unit" --invocation="${p[InvocationID]}" \
    -o cat --no-pager 2>/dev/null \
    | grep -v -e "^$unit: " -e '^Failed to start ' -e '^Starting ' \
    | tail -n 10 | cut -c1-300
}

status_hint() {
  local where=""
  [ "${scope[0]}" = --user ] && where=" --user"
  printf 'systemctl%s status %s' "$where" "$unit"
}

looping() {
  local f="$dir/$unit.looping" since="" count="" last="" paged=""
  read -r since count last paged < "$f" 2>/dev/null || true
  if [ -z "$last" ] || [ $((now - last)) -gt "$loop_window" ]; then
    since=$now
    count=0
    paged=0
  fi
  count=$((${count:-0} + 1))
  paged=${paged:-0}
  local page=""
  if [ "$count" -eq "$loop_threshold" ]; then
    page="CRASH LOOP on $host: $unit failed $count times in $(human $((now - since))) (${p[Result]:-unknown}, exit ${p[ExecMainStatus]:-?})"
  elif [ "$count" -gt "$loop_threshold" ] && [ $((now - paged)) -ge "$loop_repeat" ]; then
    page="STILL LOOPING on $host: $unit, $count failures over $(human $((now - since)))"
  fi
  if [ -n "$page" ]; then
    local tail
    tail="$(journal_tail)"
    [ -n "$tail" ] && page+=$'\n\n'"$tail"
    page+=$'\n\n'"Pages again hourly while it keeps looping; nothing is sent when it settles. $(status_hint)"
    telegram-notify "$page"
    paged=$now
  fi
  printf '%s %s %s %s\n' "$since" "$count" "$now" "$paged" > "$f"
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
    looping
    exit 0
  fi

  local f="$dir/$unit.failing" since count rest
  if [ -e "$f" ]; then
    read -r since count rest < "$f" || true
    printf '%s %s %s\n' "${since:-$now}" $((${count:-0} + 1)) "$now" > "$f"
    exit 0
  fi
  printf '%s 1 %s\n' "$now" "$now" > "$f"

  local tail
  tail="$(journal_tail)"
  local msg
  msg="FAILED on $host: $unit (${p[Result]:-unknown}, exit ${p[ExecMainStatus]:-?})"
  [ -n "$tail" ] && msg+=$'\n\n'"$tail"
  msg+=$'\n\n'"Quiet until it succeeds again. $(status_hint)"
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
