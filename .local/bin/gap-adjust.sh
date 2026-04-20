#!/usr/bin/env bash
delta=$1
current=$(hyprctl getoption general:gaps_out 2>/dev/null | grep -oP 'int: \K[0-9]+')
current=${current:-20}
if [[ "$delta" == "0" ]]; then
    new=0
else
    new=$((current + delta))
    [[ $new -lt 0 ]] && new=0
fi
hyprctl keyword general:gaps_out $new
hyprctl keyword general:gaps_in $((new / 4 > 0 ? new / 4 : 0))
