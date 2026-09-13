#!/usr/bin/env bash
set -euo pipefail

KINDLE_HOST="${KINDLE_HOST:-100.80.53.92}"
KINDLE_PORT="${KINDLE_PORT:-22}"
SETTINGS=/mnt/us/koreader/settings.reader.lua
BACKUP=/mnt/us/mandragora/state/settings.reader.pre-lockscreen.lua
ART_DIR=/mnt/us/mandragora/art

SSH=(ssh -p "$KINDLE_PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 "root@$KINDLE_HOST")

echo "kindle-lockscreen: $KINDLE_HOST"

"${SSH[@]}" bash -s <<REMOTE
set -e
pkill -f reader.lua 2>/dev/null || true
pkill -f koreader.sh 2>/dev/null || true
i=0
while pgrep -f reader.lua >/dev/null 2>&1 && [ \$i -lt 20 ]; do sleep 1; i=\$((i+1)); done
sleep 2
cp $SETTINGS $BACKUP
awk -v dir="$ART_DIR" '
FNR==NR { if (\$0 ~ /\["screensaver_dir"\] = /) seen=1; next }
\$0 ~ /\["screensaver_type"\] = / { print "    [\"screensaver_type\"] = \"random_image\","; next }
\$0 ~ /\["screensaver_show_message"\] = / { print "    [\"screensaver_show_message\"] = false,"; next }
\$0 ~ /\["screensaver_dir"\] = / { print "    [\"screensaver_dir\"] = \"" dir "\","; next }
\$0 ~ /\["screensaver_delay"\] = / { print; if (!seen) { print "    [\"screensaver_dir\"] = \"" dir "\","; seen=1 }; next }
{ print }
' $BACKUP $BACKUP > $SETTINGS
if ! /mnt/us/koreader/luajit -e 'assert(loadfile("$SETTINGS"))' 2>/dev/null; then
  cp $BACKUP $SETTINGS
  echo "kindle-lockscreen: patched file failed to parse, restored backup" >&2
  exit 1
fi
( setsid /bin/sh /mnt/us/koreader/koreader.sh >/dev/null 2>&1 & ) &
REMOTE

echo "kindle-lockscreen: applied, KOReader restarting (backup at $BACKUP)"
