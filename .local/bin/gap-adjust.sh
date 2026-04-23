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
get_local_out() {
    local ws
    ws=$(get_ws_id)
    hyprctl workspacerules 2>/dev/null \
        | awk "/Workspace rule $ws:/{found=1} found && /gapsOut:/{print \$2; exit}"
}

apply() {
    local scope=$1 out=$2 incremental=$3
    local in=$(( out / 4 > 0 ? out / 4 : 0 ))
    if [[ $scope == local ]]; then
        local ws
        ws=$(get_ws_id)
        hyprctl keyword workspace "$ws, gapsout:$out, gapsin:$in" >/dev/null
        # Workspace rules don't apply until re-entering the workspace; bounce to force it
        local bounce=$(( ws % 9 + 1 ))
        [[ $bounce -eq $ws ]] && bounce=$(( ws - 1 ))
        if [[ $incremental == 1 ]]; then
            hyprctl keyword animations:enabled 0 >/dev/null 2>&1
            hyprctl --batch "dispatch workspace $bounce ; dispatch workspace $ws" >/dev/null 2>&1
            hyprctl keyword animations:enabled 1 >/dev/null 2>&1
        else
            hyprctl --batch "dispatch workspace $bounce ; dispatch workspace $ws" >/dev/null 2>&1
        fi
    else
        hyprctl keyword general:gaps_out "$out" >/dev/null
        hyprctl keyword general:gaps_in  "$in"  >/dev/null
    fi
}

incremental=0
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
        incremental=1
    fi
else
    scope=$1
    arg=$2
    if [[ $scope == local ]]; then
        cur=$(get_local_out)
        [[ -z $cur ]] && cur=$(get_global_out)
    else
        cur=$(get_global_out)
    fi
    cur=${cur:-20}
    case "$arg" in
        plus)   value=$(( cur + delta )); incremental=1 ;;
        minus)  value=$(( cur - delta )); (( value < 0 )) && value=0; incremental=1 ;;
        zero)   value=0 ;;
        ''|*[!0-9-]*)
            echo "usage: gap-adjust [all|local] <N|plus|minus|zero>" >&2
            exit 1 ;;
        *)
            if (( arg < 0 )); then
                value=$(( cur + arg )); (( value < 0 )) && value=0; incremental=1
            else
                value=$arg
            fi ;;
    esac
fi

apply "$scope" "$value" "$incremental"
