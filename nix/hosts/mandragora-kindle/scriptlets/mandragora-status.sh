#!/bin/sh
# Name: mandragora ▸ status
# Author: mandragora
M=/mnt/us/mandragora
FB=/var/local/kmc/bin/fbink
TS="$M/bin/tailscale --socket=$M/state/tailscaled.sock"
ip=$(ip -4 addr show wlan0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1)
bat=$(cat /sys/class/power_supply/*/capacity 2>/dev/null | head -1)
fw=$(cut -d' ' -f2 /etc/version.txt 2>/dev/null | head -1)
tsip=$($TS ip -4 2>/dev/null | head -1)
tsst=$($TS status --peers=false 2>/dev/null | awk 'NR==1{print $NF}')
free=$(df -h /mnt/us 2>/dev/null | awk 'NR==2{print $4}')
"$FB" -c -q
"$FB" -q -m -y 8  -S 3 "mandragora"
"$FB" -q -m -y 14 "kindle ▸ paperwhite 12  ·  fw $fw"
"$FB" -q -m -y 17 "wlan  $ip"
"$FB" -q -m -y 19 "tailnet  ${tsip:-not joined}  ${tsst}"
"$FB" -q -m -y 21 "battery ${bat}%   free $free"
"$FB" -q -m -y 24 "dropbear $(pgrep -f $M/bin/dropbear >/dev/null && echo up || echo down)   tailscaled $(pgrep -f $M/bin/tailscaled >/dev/null && echo up || echo down)"
"$FB" -q -m -y 28 "$(date '+%Y-%m-%d %H:%M')"
sleep 8
