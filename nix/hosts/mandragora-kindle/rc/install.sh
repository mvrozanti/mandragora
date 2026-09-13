#!/bin/sh
set -u
M=/mnt/us/mandragora
JOB=/etc/upstart/mandragora.conf
FB=/var/local/kmc/bin/fbink

say() { echo "$*"; [ -x "$FB" ] && "$FB" -q -y -3 "$*" 2>/dev/null; }

[ "$(id -u)" = 0 ] || { echo "must run as root"; exit 1; }
[ "$(uname -m)" = armv7l ] || { echo "unexpected arch $(uname -m), refusing"; exit 1; }
[ -f /lib/ld-linux-armhf.so.3 ] || { echo "not armhf, refusing"; exit 1; }
[ -x "$M/bin/tailscaled" ] || chmod +x "$M/bin/"* 2>/dev/null
"$M/bin/tailscale" version >/dev/null 2>&1 || { echo "tailscale binary does not run here"; exit 1; }

OLD=/bin/chattr; NEW=/bin/chattr.e2fsprogs
CHATTR=$OLD; [ -f "$NEW" ] && CHATTR=$NEW

say "mandragora: installing boot job"
mntroot rw >/dev/null 2>&1 || mount -o remount,rw / || { echo "cannot remount rootfs rw"; exit 1; }
[ -f "$JOB" ] && $CHATTR -i "$JOB" 2>/dev/null
cp -f "$M/rc/mandragora.conf" "$JOB" && chmod 0664 "$JOB" && $CHATTR +i "$JOB" 2>/dev/null
sync
mntroot ro >/dev/null 2>&1 || mount -o remount,ro /
[ -f "$JOB" ] && echo "installed $JOB" || { echo "install failed"; exit 1; }

say "mandragora: installing scriptlets"
for s in "$M"/scriptlets/*.sh; do
	[ -f "$s" ] && cp -f "$s" /mnt/us/documents/ && echo "scriptlet: $(basename "$s") -> /mnt/us/documents/"
done

say "mandragora: starting services"
/bin/sh "$M/rc/start.sh"
sleep 4
pgrep -f "$M/bin/tailscaled" >/dev/null && echo "tailscaled: running" || echo "tailscaled: NOT running (see $M/log)"
pgrep -f "$M/bin/dropbear" >/dev/null && echo "dropbear: running" || echo "dropbear: not running yet (binary pending)"

i=0
while [ $i -lt 40 ]; do
	url=$(grep -o 'https://login.tailscale.com/[A-Za-z0-9/_-]*' "$M/log/tailscale-up.log" 2>/dev/null | tail -1)
	[ -n "$url" ] && break
	"$M/bin/tailscale" --socket="$M/state/tailscaled.sock" status >/dev/null 2>&1 && st=$("$M/bin/tailscale" --socket="$M/state/tailscaled.sock" status --peers=false 2>/dev/null | head -1) && case "$st" in *"100."*) echo "tailscale: already joined ($st)"; break;; esac
	sleep 2; i=$((i+1))
done
if [ -n "${url:-}" ]; then
	echo "TAILSCALE_LOGIN_URL=$url"
	say "mandragora: open the login URL shown on the desktop"
fi
echo "tailscale-up.log tail:"; tail -5 "$M/log/tailscale-up.log" 2>/dev/null
