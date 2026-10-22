#!/usr/bin/env bash
ICON="󰆼"
THRESHOLD=50
STATE=/tmp/disk-io-state

human() {
  local b=$1
  if   [ "$b" -ge 1073741824 ]; then printf '%d GB/s' $(( b / 1073741824 ))
  elif [ "$b" -ge 1048576 ];    then printf '%d MB/s' $(( b / 1048576 ))
  elif [ "$b" -ge 1024 ];       then printf '%d KB/s' $(( b / 1024 ))
  else printf '%d B/s' "$b"; fi
}

read_sectors=0
write_sectors=0
while read -r _ _ name _ _ rd _ _ _ wr _; do
  case "$name" in loop*|ram*|zram*) continue ;; esac
  [ -e "/sys/class/block/$name/partition" ] && continue
  read_sectors=$(( read_sectors + rd ))
  write_sectors=$(( write_sectors + wr ))
done < /proc/diskstats

now=$(date +%s)
read -r prs pws ptime 2>/dev/null < "$STATE" || true
printf '%s %s %s\n' "$read_sectors" "$write_sectors" "$now" > "$STATE"

rbytes=0
wbytes=0
if [ -n "$prs" ] && [ -n "$pws" ] && [ -n "$ptime" ] \
   && [ "$now" -gt "$ptime" ] \
   && [ "$read_sectors" -ge "$prs" ] && [ "$write_sectors" -ge "$pws" ]; then
  dt=$(( now - ptime ))
  rbytes=$(( (read_sectors - prs) * 512 / dt ))
  wbytes=$(( (write_sectors - pws) * 512 / dt ))
fi

press=$(sed -n 's/^some avg10=\([0-9.]*\).*/\1/p' /proc/pressure/io 2>/dev/null)
press=${press:-0}
pressured=$(awk -v p="$press" -v t="$THRESHOLD" 'BEGIN { print (p >= t) ? 1 : 0 }')

icon="$ICON"
cls=""
if [ "$pressured" = 1 ]; then
  cls="pressured"
fi

rate_total=$(human "$(( rbytes + wbytes ))")
rate_read=$(human "$rbytes")
rate_write=$(human "$wbytes")
printf '{"text": "%s %s", "class": "%s", "tooltip": "read %s  write %s\\npressure some avg10: %s%%"}\n' \
  "$icon" "$rate_total" "$cls" "$rate_read" "$rate_write" "$press"
