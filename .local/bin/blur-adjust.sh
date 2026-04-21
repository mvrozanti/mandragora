#!/usr/bin/env bash
# Usage: blur-adjust <delta|set N|toggle>
#   blur-adjust +1 / -1 / 3 / -3   adjust decoration:blur:size by delta
#   blur-adjust set 8              set absolute size
#   blur-adjust toggle             toggle decoration:blur:enabled
min=0
max=20

get_size() {
    hyprctl getoption decoration:blur:size -j 2>/dev/null \
        | grep -oP '"int":\s*\K-?[0-9]+' | head -1
}
get_enabled() {
    hyprctl getoption decoration:blur:enabled -j 2>/dev/null \
        | grep -oP '"int":\s*\K-?[0-9]+' | head -1
}

arg=${1:-+1}

if [[ $arg == toggle ]]; then
    cur=$(get_enabled); cur=${cur:-1}
    new=$(( cur == 0 ? 1 : 0 ))
    hyprctl keyword decoration:blur:enabled "$new" >/dev/null
    exit 0
fi

cur=$(get_size); cur=${cur:-8}
case "$arg" in
    set) new=$2 ;;
    *)   new=$(( cur + arg )) ;;
esac

(( new < min )) && new=$min
(( new > max )) && new=$max

hyprctl keyword decoration:blur:size "$new" >/dev/null
