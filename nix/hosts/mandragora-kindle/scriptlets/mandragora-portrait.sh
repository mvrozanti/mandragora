#!/bin/sh
# Name: mandragora ▸ portrait
# Author: mandragora
M=/mnt/us/mandragora
FB=/var/local/kmc/bin/fbink
ART=$M/art
STATE=$M/state/portrait.last

pick() {
  set -- "$ART"/*.png "$ART"/*.jpg "$ART"/*.jpeg
  last=$(cat "$STATE" 2>/dev/null)
  first=""
  next=""
  take=0
  for f in "$@"; do
    [ -f "$f" ] || continue
    [ -z "$first" ] && first="$f"
    [ "$take" = 1 ] && { next="$f"; break; }
    [ "$f" = "$last" ] && take=1
  done
  [ -n "$next" ] && echo "$next" || echo "$first"
}

img=$(pick)
if [ -z "$img" ] || [ ! -f "$img" ]; then
  "$FB" -q -c -m -y 12 -S 2 "no art in $ART"
  sleep 4
  exit 0
fi

echo "$img" > "$STATE"
"$FB" -q -c -f --image file="$img",halign=center,valign=center --dither --waveform GC16
