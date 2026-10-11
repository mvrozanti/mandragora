#!/usr/bin/env bash
frames=(✶ · '*' ✻)
printf '%s' "${frames[$(( $(date +%s) % 4 ))]}"
