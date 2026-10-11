#!/usr/bin/env bash
frames=(· ✢ '*' ✶ ✻ ✽)
i=$(( (10#$(date +%3N) / 100) % 10 ))
[ "$i" -gt 5 ] && i=$(( 10 - i ))
printf '%s' "${frames[$i]}"
