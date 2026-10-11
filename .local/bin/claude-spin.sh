#!/usr/bin/env bash
frames=(✶ · '*' ✻)
printf '%s' "${frames[$(( (10#$(date +%3N) / 100) % 4 ))]}"
