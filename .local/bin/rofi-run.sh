#!/usr/bin/env bash
exec rofi -show run \
    -run-list-command rofi-run-list \
    -run-command "rofi-run-exec {cmd}" \
    -run-shell-command "kitty -e rofi-run-exec {cmd}"
