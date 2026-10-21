#!/usr/bin/env bash
if [ "$1" = rofi-run-list ]; then
  exec rofi-run-list
fi
exec zsh -i -c "$*"
