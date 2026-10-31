#!/usr/bin/env bash
EXPECTED_MBPS=1000

human() {
  local b=$1
  if   [ "$b" -ge 1073741824 ]; then printf '%d GB/s' $(( b / 1073741824 ))
  elif [ "$b" -ge 1048576 ];    then printf '%d MB/s' $(( b / 1048576 ))
  elif [ "$b" -ge 1024 ];       then printf '%d KB/s' $(( b / 1024 ))
  else printf '%d B/s' "$b"; fi
}

link_label() {
  local mbps=$1
  if [ "$mbps" -ge 1000 ]; then printf '%dG' $(( mbps / 1000 ))
  else printf '%dM' "$mbps"; fi
}

iface=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
if [ -z "$iface" ]; then
  printf '{"text": "disconnected", "class": "disconnected", "tooltip": "no default route"}\n'
  exit
fi

rx=$(cat "/sys/class/net/$iface/statistics/rx_bytes" 2>/dev/null || echo 0)
tx=$(cat "/sys/class/net/$iface/statistics/tx_bytes" 2>/dev/null || echo 0)
now=$(date +%s)
state=/tmp/net-rate-$iface
drx=0
dtx=0
if read -r prx ptx pt 2>/dev/null < "$state" && [ "$now" -gt "$pt" ]; then
  dt=$(( now - pt ))
  drx=$(( (rx - prx) / dt ))
  dtx=$(( (tx - ptx) / dt ))
fi
printf '%s %s %s\n' "$rx" "$tx" "$now" > "$state"

speed=$(cat "/sys/class/net/$iface/speed" 2>/dev/null || echo -1)
duplex=$(cat "/sys/class/net/$iface/duplex" 2>/dev/null || echo unknown)
wired=1
[ -d "/sys/class/net/$iface/wireless" ] && wired=0

cls=""
prefix=""
link="link speed unknown"
if [ "$wired" = 1 ] && [ "$speed" -gt 0 ]; then
  link="link $speed Mb/s $duplex duplex"
  if [ "$speed" -lt "$EXPECTED_MBPS" ] || [ "$duplex" != full ]; then
    cls="degraded"
    prefix="󰈀 $(link_label "$speed") "
  fi
fi

rate="↑ $(human "$dtx") ↓ $(human "$drx")"
printf '{"text": "%s%s", "class": "%s", "tooltip": "%s\\n%s"}\n' \
  "$prefix" "$rate" "$cls" "$iface" "$link"
