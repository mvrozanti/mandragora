#!/bin/sh
exec 2>/dev/null

filename=$(basename -- "$1")
filesize=$(du -Hh -- "$1" | cut -f 1)
geometry="${2}x${3}"
tags=$(identify -format '%[IPTC:2:25]' ":$1" | tr ';' ',')

s=" | "
echo "${filesize}${s}${geometry}${tags:+$s}${tags}${s}${filename}"
