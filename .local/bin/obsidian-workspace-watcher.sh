#!/usr/bin/env bash
socket="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

follow() {
    local addr="$1"
    hyprctl dispatch movetoworkspacesilent "41,address:$addr" >/dev/null 2>&1
    hyprctl dispatch workspace 41 >/dev/null 2>&1
    hyprctl dispatch focuswindow "address:$addr" >/dev/null 2>&1
}

socat -U - "UNIX-CONNECT:$socket" | while IFS= read -r line; do
    [[ "$line" != openwindow* ]] && continue
    data="${line#openwindow>>}"
    addr="0x${data%%,*}"
    rest="${data#*,}"
    class_field="${rest#*,}"
    class="${class_field%%,*}"
    title="${class_field#*,}"

    if [[ "$class" == "obsidian" ]] || [[ "$title" == *Obsidian* ]]; then
        follow "$addr"
        continue
    fi

    if [[ "$class" == "electron" ]]; then
        (
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                sleep 0.4
                t=$(hyprctl clients -j 2>/dev/null | jq -r --arg a "$addr" '.[] | select(.address == $a) | .title // empty')
                [[ -z "$t" ]] && exit 0
                if [[ "$t" == *Obsidian* ]]; then
                    follow "$addr"
                    exit 0
                fi
            done
        ) &
    fi
done
