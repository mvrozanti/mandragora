#!/usr/bin/env bash
dir=$(dirname -- "$imv_current_file")

readarray -t images < <(find "$dir" -maxdepth 1 -type f \( \
    -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o \
    -iname "*.gif" -o -iname "*.bmp" -o -iname "*.tiff" -o \
    -iname "*.tif" -o -iname "*.webp" -o -iname "*.svg" -o \
    -iname "*.xpm" -o -iname "*.ico" -o -iname "*.avif" \
\) | sort)

(( ${#images[@]} == 0 )) && exit 0

idx=0
for i in "${!images[@]}"; do
    [[ "${images[$i]}" == "$imv_current_file" ]] && idx=$i && break
done

setsid imv -n "$idx" "${images[@]}" &
