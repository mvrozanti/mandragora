#!/usr/bin/env bash
IDENTIFIER="$1"
CMD="$2"

LOG="/tmp/smart-launch.log"
echo "--- $(date) ---" >> "$LOG"
echo "Searching for: $IDENTIFIER" >> "$LOG"

# Try to find window by any field matching the identifier
ID_LOWER=$(echo "$IDENTIFIER" | tr '[:upper:]' '[:lower:]')
READ=$(hyprctl clients -j | jq -r --arg id "$ID_LOWER" '.[] | select((.class | ascii_downcase) == $id or (.initialClass | ascii_downcase) == $id or (.title | ascii_downcase) == $id or (.initialTitle | ascii_downcase) == $id or (.title | ascii_downcase | contains($id))) | [.address, (.workspace.id | tostring), .class, .title] | @tsv' | head -1)

if [ -n "$READ" ]; then
    ADDR=$(echo "$READ" | cut -f1)
    WS=$(echo "$READ" | cut -f2)
    CLASS=$(echo "$READ" | cut -f3)
    TITLE=$(echo "$READ" | cut -f4)
    echo "Found: Address $ADDR, WS $WS, Class $CLASS, Title $TITLE" >> "$LOG"
    hyprctl dispatch workspace "$WS"
    hyprctl dispatch focuswindow "address:$ADDR"
    hyprctl dispatch bringactivetotop
else
    echo "Not found. Executing: $CMD" >> "$LOG"
    hyprctl dispatch exec "$CMD"
    for _ in $(seq 1 20); do
        sleep 0.2
        WS=$(hyprctl clients -j | jq -r --arg id "$ID_LOWER" '.[] | select((.class | ascii_downcase) == $id or (.initialClass | ascii_downcase) == $id) | .workspace.id' | head -1)
        if [ -n "$WS" ] && [ "$WS" != "null" ]; then
            echo "Window appeared on WS $WS, switching" >> "$LOG"
            hyprctl dispatch workspace "$WS"
            hyprctl dispatch focuswindow "class:$IDENTIFIER"
            break
        fi
    done
fi
