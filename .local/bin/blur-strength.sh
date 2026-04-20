#!/usr/bin/env bash
if [[ $# -ne 1 ]]; then
    echo "usage: $0 [+N|-N|N]" >&2
    exit 1
fi
arg="$1"
current=$(hyprctl getoption decoration:blur:size -j | jq '.int')
case "$arg" in
    +*) new=$(( current + ${arg#+} )) ;;
    -*) new=$(( current - ${arg#-} )) ;;
    *)  new="$arg" ;;
esac
(( new < 1 )) && new=1
hyprctl keyword decoration:blur:size "$new"
notify-send "Blur" "size: $new"
