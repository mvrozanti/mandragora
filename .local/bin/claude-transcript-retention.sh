#!/usr/bin/env bash
settings="$HOME/.claude/settings.json"
[ -f "$settings" ] || echo '{}' > "$settings"
if [ "$(jq -r '.cleanupPeriodDays // empty' "$settings")" != "90" ]; then
    jq '.cleanupPeriodDays = 90' "$settings" > "$settings.tmp"
    mv "$settings.tmp" "$settings"
fi
