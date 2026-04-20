#!/usr/bin/env bash
BINARY="${1##*/}"

is_terminal_app() {
    local bin="$1"
    local found_desktop=false
    for dir in \
        /run/current-system/sw/share/applications \
        /etc/profiles/per-user/m/share/applications \
        "$HOME/.local/share/applications"; do
        [ -d "$dir" ] || continue
        for f in "$dir"/*.desktop; do
            [ -f "$f" ] || continue
            if grep -qs "^Exec=${bin}" "$f"; then
                found_desktop=true
                grep -qs "^Terminal=true" "$f" && return 0 || return 1
            fi
        done
    done
    [ "$found_desktop" = false ] && return 0
    return 1
}

if is_terminal_app "$BINARY"; then
    exec kitty -e "$@"
else
    exec "$@"
fi
