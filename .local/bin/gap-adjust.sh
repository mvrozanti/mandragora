#!/usr/bin/env bash
# Usage:
#   gap-adjust <delta>                       # back-compat, global delta (0 = reset to 0)
#   gap-adjust {all|local} <N|plus|minus|zero>
#
# "all"   adjusts general:gaps_{in,out} globally
# "local" adjusts gapsin/gapsout for the active workspace only
delta=5

get_global_out() {
    # gaps_out is a "custom" 4-tuple ("N N N N"); also accept legacy "int" form
    hyprctl getoption general:gaps_out -j 2>/dev/null \
        | grep -oP '"(custom|int)":\s*"?\K-?[0-9]+' | head -1
}
get_ws_id() {
    hyprctl activeworkspace -j 2>/dev/null \
        | grep -oP '"id":\s*\K-?[0-9]+' | head -1
}

apply() {
    local scope=$1 out=$2
    local in=$(( out / 4 > 0 ? out / 4 : 0 ))
    if [[ $scope == local ]]; then
        local ws
        ws=$(get_ws_id)
        hyprctl keyword workspace "$ws, gapsout:$out, gapsin:$in" >/dev/null
    else
        hyprctl keyword general:gaps_out "$out" >/dev/null
        hyprctl keyword general:gaps_in  "$in"  >/dev/null
    fi
}

if [[ $# -eq 1 ]]; then
    # back-compat: single numeric arg = delta against global (0 = zero)
    scope=all
    a=$1
    if [[ $a == 0 ]]; then
        value=0
    else
        cur=$(get_global_out); cur=${cur:-20}
        value=$(( cur + a ))
        (( value < 0 )) && value=0
    fi
else
    scope=$1
    arg=$2
    cur=$(get_global_out); cur=${cur:-20}
    case "$arg" in
        plus)   value=$(( cur + delta )) ;;
        minus)  value=$(( cur - delta )); (( value < 0 )) && value=0 ;;
        zero)   value=0 ;;
        ''|*[!0-9-]*)
            echo "usage: gap-adjust [all|local] <N|plus|minus|zero>" >&2
            exit 1 ;;
        *)
            if (( arg < 0 )); then
                value=$(( cur + arg )); (( value < 0 )) && value=0
            else
                value=$arg
            fi ;;
    esac
fi

apply "$scope" "$value"
