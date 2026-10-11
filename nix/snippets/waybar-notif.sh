#!/usr/bin/env bash
bell=$''
bell_slash=$''

emit() {
  if swaync-client -D -sw 2>/dev/null | grep -q true; then
    printf '{"text": "%s", "class": "dnd"}\n' "$bell_slash"
  else
    printf '{"text": "%s", "class": "active"}\n' "$bell"
  fi
}

emit
stdbuf -oL swaync-client -swb -sw | while IFS= read -r line; do
  case "$line" in
    *dnd-notification*) printf '{"text": "%s", "class": "dnd"}\n' "$bell_slash" ;;
    *)                 printf '{"text": "%s", "class": "active"}\n' "$bell" ;;
  esac
done
