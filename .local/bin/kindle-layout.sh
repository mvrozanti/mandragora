#!/usr/bin/env bash
set -euo pipefail

KINDLE_HOST="${KINDLE_HOST:-100.80.53.92}"
KINDLE_PORT="${KINDLE_PORT:-22}"
REPO="${MANDRAGORA_REPO:-/etc/nixos/mandragora}"
LAYOUT="$REPO/nix/hosts/mandragora-kindle/simpleui/layout.conf"
SETTINGS=/mnt/us/koreader/settings/simpleui/sui_settings.lua
BACKUP=/mnt/us/mandragora/sui_settings.pre-layout.lua

SSH=(ssh -p "$KINDLE_PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 "root@$KINDLE_HOST")

[ -f "$LAYOUT" ] || { echo "kindle-layout: no layout at $LAYOUT" >&2; exit 1; }

rows=()
while IFS= read -r line; do
  [ -z "${line// }" ] && continue
  case "$line" in \#*) continue ;; esac
  rows+=("$line")
done < "$LAYOUT"

[ "${#rows[@]}" -gt 0 ] || { echo "kindle-layout: layout is empty" >&2; exit 1; }

mapfile -t instances < <("${SSH[@]}" "awk '/\[\"simpleui_qa_row_instances\"\]/,/^    },\$/' $SETTINGS | grep -oE 'quick_actions_row_[a-z0-9]+'")

[ "${#instances[@]}" -ge "${#rows[@]}" ] || {
  echo "kindle-layout: device has ${#instances[@]} quick-action rows, layout wants ${#rows[@]}" >&2
  echo "kindle-layout: add rows in SimpleUI settings first" >&2
  exit 1
}

echo "kindle-layout: $KINDLE_HOST"
for i in "${!rows[@]}"; do
  echo "  ${instances[$i]}: ${rows[$i]}"
done

patch=$(mktemp)
{
  echo "BEGIN { split(\"\", want) }"
  for i in "${!rows[@]}"; do
    key="simpleui_hs_qa_${instances[$i]}_items"
    printf 'want["%s"] = "%s"\n' "$key" "${rows[$i]}" | sed 's/^/BEGIN { /; s/$/ }/'
  done
  cat <<'AWK'
/^    \["simpleui_hs_qa_quick_actions_row_[a-z0-9]+_items"\] = \{$/ {
  key = $0
  sub(/^    \["/, "", key); sub(/"\] = \{$/, "", key)
  if (key in want) { emit(key); seen[key] = 1; skip = 1; next }
}
skip && /^    \},$/ { skip = 0; next }
skip { next }
/^    \["simpleui_hs_quick_actions_row_[a-z0-9]+_enabled"\]/ {
  for (k in want) if (!(k in seen)) { emit(k); seen[k] = 1 }
}
{ print }
function emit(k,   n, parts, j) {
  printf "    [\"%s\"] = {\n", k
  n = split(want[k], parts, " ")
  for (j = 1; j <= n; j++) printf "        [%d] = \"%s\",\n", j, parts[j]
  print "    },"
}
AWK
} > "$patch"

"${SSH[@]}" "cat > /tmp/kindle-layout.awk" < "$patch"
rm -f "$patch"

"${SSH[@]}" bash -s <<REMOTE
set -e
pkill -f reader.lua 2>/dev/null || true
pkill -f koreader.sh 2>/dev/null || true
i=0
while pgrep -f reader.lua >/dev/null 2>&1 && [ \$i -lt 20 ]; do sleep 1; i=\$((i+1)); done
sleep 2
cp $SETTINGS $BACKUP
awk -f /tmp/kindle-layout.awk $BACKUP > $SETTINGS
if ! /mnt/us/koreader/luajit -e 'assert(loadfile("$SETTINGS"))' 2>/dev/null; then
  cp $BACKUP $SETTINGS
  echo "kindle-layout: patched file failed to parse, restored backup" >&2
  exit 1
fi
if [ -x /var/local/kmc/bin/kpm ]; then
  /var/local/kmc/bin/kpm launch koreader --asap >/dev/null 2>&1
else
  ( setsid /bin/sh /mnt/us/koreader/koreader.sh >/dev/null 2>&1 & ) &
fi
i=0
while [ \$i -lt 45 ]; do pgrep -f reader.lua >/dev/null 2>&1 && break; i=\$((i+1)); sleep 1; done
pgrep -f reader.lua >/dev/null 2>&1 || echo "WARNING: koreader did not come back — device is on the amazon ui" >&2
REMOTE

echo "kindle-layout: applied, KOReader restarting (backup at $BACKUP)"
