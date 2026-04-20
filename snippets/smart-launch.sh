#!/usr/bin/env bash
CLASS="$1"
CMD="$2"

READ=$(hyprctl clients -j | jq -r ".[] | select(.class == \"$CLASS\") | [.address, (.workspace.id | tostring)] | @tsv" | head -1)

if [ -n "$READ" ]; then
    ADDR=$(echo "$READ" | cut -f1)
    WS=$(echo "$READ" | cut -f2)
    hyprctl dispatch workspace "$WS"
    hyprctl dispatch focuswindow "address:$ADDR"
else
    hyprctl dispatch exec "$CMD"
fi
