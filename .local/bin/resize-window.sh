#!/usr/bin/env bash
if [[ $# -ne 2 ]]; then
    echo "usage: $0 <width> <height>" >&2
    exit 1
fi
hyprctl dispatch resizeactive exact "$1" "$2"
