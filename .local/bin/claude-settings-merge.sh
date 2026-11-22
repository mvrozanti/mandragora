#!/usr/bin/env bash
declared="$1"
settings="$HOME/.claude/settings.json"
mkdir -p "$(dirname "$settings")"
[ -f "$settings" ] || echo '{}' > "$settings"
merged=$(jq -s '.[0] * .[1]' "$settings" "$declared")
[ "$merged" = "$(jq . "$settings")" ] && exit 0
printf '%s\n' "$merged" > "$settings.tmp"
mv -f "$settings.tmp" "$settings"
