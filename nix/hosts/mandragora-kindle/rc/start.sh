#!/bin/sh
i=0
while [ $i -lt 90 ]; do
  [ -x /mnt/us/mandragora/bin/tailscaled ] && break
  sleep 2
  i=$((i+1))
done

M=/mnt/us/mandragora
S=$M/state
L=$M/log
mkdir -p "$S" "$L" "$M/scriptlets"
chmod 700 "$S"
export PATH="$M/bin:$PATH"

FB=/var/local/kmc/bin/fbink
log() { echo "$(date '+%F %T') $*" >> "$L/start.log"; }
log "boot: start.sh (waited ${i}x2s for /mnt/us)"
[ -x "$FB" ] && "$FB" -q -y -2 "mandragora ▸ starting services" 2>/dev/null

if [ -x "$M/bin/dropbear" ] && ! pgrep -f "$M/bin/dropbear" >/dev/null 2>&1; then
  [ -f "$S/dropbear_ed25519_host_key" ] || "$M/bin/dropbearkey" -t ed25519 -f "$S/dropbear_ed25519_host_key" >>"$L/dropbear.log" 2>&1
  H=$(grep "^root:" /etc/passwd | cut -d: -f6)
  H=${H:-/tmp/root}
  mkdir -p "$H/.ssh"
  chmod g-w,o-w "$H" "$H/.ssh"
  cp "$M/rc/authorized_keys" "$H/.ssh/authorized_keys" && chmod 600 "$H/.ssh/authorized_keys"
  nohup "$M/bin/dropbear" -r "$S/dropbear_ed25519_host_key" -p 2223 -s -g -E >>"$L/dropbear.log" 2>&1 &
  log "dropbear started on 2223 (key-only, home=$H)"
fi

if ! pgrep -f "$M/bin/tailscaled" >/dev/null 2>&1; then
  nohup "$M/bin/tailscaled" \
    --tun=userspace-networking \
    --socks5-server=localhost:1055 \
    --outbound-http-proxy-listen=localhost:1056 \
    --state="$S/tailscaled.state" \
    --socket="$S/tailscaled.sock" \
    --statedir="$S" \
    >>"$L/tailscaled.log" 2>&1 &
  log "tailscaled started (userspace)"
  i=0; while [ $i -lt 30 ] && [ ! -S "$S/tailscaled.sock" ]; do sleep 1; i=$((i+1)); done
  "$M/bin/tailscale" --socket="$S/tailscaled.sock" up --ssh --hostname=kindle --accept-dns=false >>"$L/tailscale-up.log" 2>&1 &
fi

log "boot: start.sh done"
