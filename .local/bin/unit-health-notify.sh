#!/usr/bin/env bash
set -uo pipefail

mode="${1:-}"
unit="${2:-}"
[ -n "$mode" ] || exit 0
[ -n "$unit" ] || [ "$mode" = sweep ] || exit 0

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
down_settle=300
undelivered=0

send() {
  telegram-notify "$1" && return 0
  undelivered=1
  return 1
}

urgent() {
  MANDRAGORA_NOTIFY_DESKTOP=1 telegram-notify "$1" && return 0
  undelivered=1
  return 1
}

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
  { read -r since count last paged < "$f"; } 2>/dev/null || true
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
    urgent "$page" && paged=$now
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
  [ -n "${MONITOR_SERVICE_RESULT:-}" ] && p[Result]=$MONITOR_SERVICE_RESULT
  [ -n "${MONITOR_EXIT_STATUS:-}" ] && p[ExecMainStatus]=$MONITOR_EXIT_STATUS
  [ -n "${MONITOR_INVOCATION_ID:-}" ] && p[InvocationID]=$MONITOR_INVOCATION_ID

  local trig="${p[TriggeredBy]:-}"
  if [ "${p[Type]:-}" != oneshot ] && [[ $trig != *.timer* && $trig != *.path* ]]; then
    looping
    return 0
  fi

  local f="$dir/$unit.failing" since count rest
  if [ -e "$f" ]; then
    read -r since count rest < "$f" || true
    printf '%s %s %s\n' "${since:-$now}" $((${count:-0} + 1)) "$now" > "$f"
    return 0
  fi

  local tail
  tail="$(journal_tail)"
  local msg
  msg="FAILED on $host: $unit (${p[Result]:-unknown}, exit ${p[ExecMainStatus]:-?})"
  [ -n "$tail" ] && msg+=$'\n\n'"$tail"
  msg+=$'\n\n'"Quiet until it succeeds again. $(status_hint)"
  send "$msg" && printf '%s 1 %s\n' "$now" "$now" > "$f"
}

recovered() {
  local f="$dir/$unit.recovered" since count rest
  [ -e "$f" ] || return 0
  read -r since count rest < "$f" || true
  rm -f "$f"
  local dur=$((now - ${since:-$now}))
  send "RECOVERED on $host: $unit succeeded after $(human "$dur") failing (${count:-?} failed runs)"
}

sweep() {
  local name f k v since paged dead names="" lines="" where=""
  local -a due=()
  local -A down=() p=()
  [ "${scope[0]}" = --user ] && where=" --user"

  while read -r name _; do
    [ -n "$name" ] || continue
    [[ $name == unit-health-* ]] && continue
    p=()
    while IFS='=' read -r k v; do
      p[$k]="$v"
    done < <(systemctl "${scope[@]}" show "$name" \
      -p Type -p TriggeredBy -p Transient -p Result -p ExecMainStatus < /dev/null)
    [ "${p[Type]:-}" = oneshot ] && continue
    [ "${p[Transient]:-}" = yes ] && continue
    [[ ${p[TriggeredBy]:-} == *.timer* || ${p[TriggeredBy]:-} == *.path* ]] && continue

    down[$name]=1
    f="$dir/$name.down"
    since=""
    paged=""
    { read -r since paged < "$f"; } 2>/dev/null || true
    if [ -z "$since" ]; then
      printf '%s 0\n' "$now" > "$f"
      continue
    fi
    paged=${paged:-0}
    dead=$((now - since))
    if [ "$paged" -eq 0 ] && [ "$dead" -ge "$down_settle" ]; then
      lines+="$name stopped $(human "$dead") ago and is not restarting (${p[Result]:-unknown}, exit ${p[ExecMainStatus]:-?})"$'\n'
    elif [ "$paged" -gt 0 ] && [ $((now - paged)) -ge "$loop_repeat" ]; then
      lines+="$name is still down after $(human "$dead")"$'\n'
    else
      continue
    fi
    names+="${names:+, }$name"
    due+=("$name")
  done < <(systemctl "${scope[@]}" list-units --type=service --state=failed --plain --no-legend)

  for f in "$dir"/*.down; do
    [ -e "$f" ] || continue
    name="${f##*/}"
    name="${name%.down}"
    [ -n "${down[$name]:-}" ] || rm -f "$f"
  done

  [ -n "$lines" ] || return 0
  local msg="DOWN on $host: $names"$'\n\n'"$lines"
  msg+=$'\n'"Reminds hourly until each one runs again. To acknowledge one: systemctl$where reset-failed <unit>"
  urgent "$msg" || return 0
  for name in "${due[@]}"; do
    f="$dir/$name.down"
    since=""
    { read -r since paged < "$f"; } 2>/dev/null || true
    printf '%s %s\n' "${since:-$now}" "$now" > "$f"
  done
}

case "$mode" in
  failed) failed ;;
  recovered) recovered ;;
  sweep) sweep ;;
  *) echo "unknown mode $mode" >&2; exit 2 ;;
esac
exit "$undelivered"
