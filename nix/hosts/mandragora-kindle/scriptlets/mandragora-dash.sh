#!/bin/sh
# Name: mandragora ▸ dashboard
# Author: mandragora
M=/mnt/us/mandragora
FB=/var/local/kmc/bin/fbink
IMG=$M/dash/latest.png

if [ ! -f "$IMG" ]; then
  "$FB" -q -c -m -y 12 -S 2 "no dashboard yet - run kindle-dash"
  sleep 4
  exit 0
fi

"$FB" -q -c -f --image file="$IMG",halign=center,valign=center --dither --waveform GC16
