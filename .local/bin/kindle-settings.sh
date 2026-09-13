#!/usr/bin/env bash
set -euo pipefail

KINDLE_HOST="${KINDLE_HOST:-100.80.53.92}"
KINDLE_PORT="${KINDLE_PORT:-22}"
SETTINGS=/mnt/us/koreader/settings.reader.lua
BACKUP=/mnt/us/mandragora/state/settings.reader.pre-mandragora.lua
ART_DIR="${KINDLE_ART_DIR:-/mnt/us/mandragora/art}"
LIBRARY_DIR="${KINDLE_LIBRARY_DIR:-/mnt/us/documents/library/books}"

SSH=(ssh -p "$KINDLE_PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 "root@$KINDLE_HOST")

want=$(mktemp)
trap 'rm -f "$want"' EXIT
cat > "$want" <<WANT
screensaver_type	"random_image"
screensaver_show_message	false
screensaver_dir	"$ART_DIR"
home_dir	"$LIBRARY_DIR"
lastdir	"$LIBRARY_DIR"
WANT

echo "kindle-settings: $KINDLE_HOST"
sed 's/^/  /; s/\t/ = /' "$want"

"${SSH[@]}" "cat > /tmp/kindle-settings.want" < "$want"

"${SSH[@]}" bash -s <<REMOTE
set -e
pkill -f reader.lua 2>/dev/null || true
pkill -f koreader.sh 2>/dev/null || true
i=0
while pgrep -f reader.lua >/dev/null 2>&1 && [ \$i -lt 20 ]; do sleep 1; i=\$((i+1)); done
sleep 2
[ -f $BACKUP ] || cp $SETTINGS $BACKUP
cp $SETTINGS ${SETTINGS}.prev
awk '
FNR==NR {
    key = \$0; sub(/\t.*/, "", key)
    val = \$0; sub(/^[^\t]*\t/, "", val)
    want[key] = val
    next
}
{
    line = \$0
    key = line
    if (match(key, /^[[:space:]]*\["[^"]+"\][[:space:]]*=/)) {
        sub(/^[[:space:]]*\["/, "", key)
        sub(/"\][[:space:]]*=.*/, "", key)
        if (key in want) {
            printf "    [\"%s\"] = %s,\n", key, want[key]
            done[key] = 1
            next
        }
    }
    if (line ~ /^}/) {
        for (k in want) if (!(k in done)) printf "    [\"%s\"] = %s,\n", k, want[k]
    }
    print line
}
' /tmp/kindle-settings.want ${SETTINGS}.prev > $SETTINGS
if ! /mnt/us/koreader/luajit -e 'assert(loadfile("$SETTINGS"))' 2>/dev/null; then
  cp ${SETTINGS}.prev $SETTINGS
  echo "kindle-settings: patched file failed to parse, restored" >&2
  exit 1
fi
rm -f ${SETTINGS}.prev /tmp/kindle-settings.want
if [ -x /var/local/kmc/bin/kpm ]; then
  /var/local/kmc/bin/kpm launch koreader --asap >/dev/null 2>&1
else
  ( setsid /bin/sh /mnt/us/koreader/koreader.sh >/dev/null 2>&1 & ) &
fi
i=0
while [ \$i -lt 45 ]; do pgrep -f reader.lua >/dev/null 2>&1 && break; i=\$((i+1)); sleep 1; done
pgrep -f reader.lua >/dev/null 2>&1 || echo "WARNING: koreader did not come back — device is on the amazon ui" >&2
REMOTE

echo "kindle-settings: applied, KOReader restarting (first-run backup at $BACKUP)"
