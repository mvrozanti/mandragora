#!/usr/bin/env bash
if [ "${MANDRAGORA_BROWSER_HEADED:-0}" = 1 ]; then
  exec @chromium@ "$@"
fi
for arg in "$@"; do
  case "$arg" in
    --headless|--headless=*) exec @chromium@ "$@" ;;
  esac
done
exec @chromium@ --headless=new "$@"
