#!/usr/bin/env bash
set -u

LAN_IF="${NET_FAILOVER_LAN_IF:-enp8s0}"
WIFI_IF="${NET_FAILOVER_WIFI_IF:-wlan0}"
GW="${NET_FAILOVER_GW:-192.168.0.1}"
M_PRIMARY="${NET_FAILOVER_M_PRIMARY:-100}"
M_DEMOTED="${NET_FAILOVER_M_DEMOTED:-3000}"
INTERVAL="${NET_FAILOVER_INTERVAL:-4}"
PROBES="${NET_FAILOVER_PROBES:-8.8.8.8 1.1.1.1}"

RUNDIR=/run/net-failover
MODEFILE="$RUNDIR/mode"
STATEFILE="$RUNDIR/state"
mkdir -p "$RUNDIR"

probe() {
  local dev="$1" target
  for target in $PROBES; do
    if ping -I "$dev" -c1 -W2 "$target" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

lan_metric() {
  ip -4 route show default dev "$LAN_IF" 2>/dev/null \
    | grep -oE 'metric [0-9]+' | awk '{print $2}' | head -1
}

set_lan_metric() {
  local want="$1"
  [ "$(lan_metric)" = "$want" ] && return 0
  while ip -4 route del default dev "$LAN_IF" 2>/dev/null; do :; done
  ip -4 route add default via "$GW" dev "$LAN_IF" metric "$want" 2>/dev/null || true
}

write_state() {
  local new="$1" prev=""
  [ -f "$STATEFILE" ] && prev="$(cat "$STATEFILE" 2>/dev/null)"
  [ "$prev" = "$new" ] && return 0
  printf '%s\n' "$new" > "$STATEFILE"
  logger -t net-failover "uplink -> $new"
}

while :; do
  mode=auto
  [ -f "$MODEFILE" ] && mode="$(cat "$MODEFILE" 2>/dev/null)"
  case "$mode" in
    lan)
      set_lan_metric "$M_PRIMARY"
      write_state "lan (pinned)"
      ;;
    wifi)
      set_lan_metric "$M_DEMOTED"
      write_state "wifi (pinned)"
      ;;
    *)
      if probe "$LAN_IF"; then
        set_lan_metric "$M_PRIMARY"
        write_state "lan"
      elif probe "$WIFI_IF"; then
        set_lan_metric "$M_DEMOTED"
        write_state "wifi (failover)"
      else
        write_state "offline"
      fi
      ;;
  esac
  sleep "$INTERVAL"
done
