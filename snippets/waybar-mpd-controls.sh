#!/usr/bin/env bash
set -u

field=${1:?usage: $0 <toggle|single|random>}

emit() {
    local glyph class state
    case "$field" in
        toggle)
            state=$(mpc status 2>/dev/null | sed -n '2s/^\[\(.*\)\].*/\1/p')
            if [[ "$state" = playing ]]; then
                glyph=$'\ue9a4'
                class=playing
            else
                glyph=$'\ue9af'
                class=paused
            fi
            ;;
        single)
            glyph=$'\uf01e'
            mpc status 2>/dev/null | grep -q 'single: on' && class=on || class=off
            ;;
        random)
            glyph=$'\uf074'
            mpc status 2>/dev/null | grep -q 'random: on' && class=on || class=off
            ;;
        *)
            echo "unknown field: $field" >&2
            exit 1
            ;;
    esac
    printf '{"text":"%s","class":"%s"}\n' "$glyph" "$class"
}

while true; do
    if mpc status &>/dev/null; then
        emit
        mpc idle player options &>/dev/null
    else
        printf '{"text":"","class":"none"}\n'
        sleep 2
    fi
done
