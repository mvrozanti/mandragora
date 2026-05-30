#!/usr/bin/env bash
set -u

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/waybar"
STATE_FILE="$STATE_DIR/brightness.env"
SHADER_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hypr"
SHADER_FILE="$SHADER_DIR/brightness.frag"
STEP=5
MIN=20

mkdir -p "$STATE_DIR" "$SHADER_DIR"

BRIGHTNESS=on
BRIGHTNESS_VAL=100
[[ -f "$STATE_FILE" ]] && . "$STATE_FILE"
[[ "$BRIGHTNESS_VAL" =~ ^[0-9]+$ ]] || BRIGHTNESS_VAL=100
[[ "$BRIGHTNESS_VAL" -lt "$MIN" ]] && BRIGHTNESS_VAL=$MIN
[[ "$BRIGHTNESS_VAL" -gt 100 ]] && BRIGHTNESS_VAL=100

write_state() {
    cat >"$STATE_FILE" <<EOF
BRIGHTNESS=$1
BRIGHTNESS_VAL=$2
EOF
}

write_shader() {
    local f
    f=$(awk -v p="$1" "BEGIN { printf \"%.4f\", p/100 }")
    local tmp_file="$SHADER_FILE.tmp"
    cat >"$tmp_file" <<EOF
precision highp float;
varying highp vec2 v_texcoord;
uniform sampler2D tex;
void main() {
    gl_FragColor = texture2D(tex, v_texcoord) * vec4(vec3($f), 1.0);
}
EOF
    mv "$tmp_file" "$SHADER_FILE"
}

apply() {
    local pct=$1
    if [[ "$pct" -ge 100 ]]; then
        hyprctl keyword decoration:screen_shader '' >/dev/null
        return
    fi
    write_shader "$pct"
    hyprctl keyword decoration:screen_shader "$SHADER_FILE" >/dev/null
}

notify_waybar() {
    pkill -SIGRTMIN+12 waybar 2>/dev/null || true
}

set_value() {
    local v=$1
    [[ "$v" -lt "$MIN" ]] && v=$MIN
    [[ "$v" -gt 100 ]] && v=100
    BRIGHTNESS_VAL=$v
    BRIGHTNESS=on
    apply "$BRIGHTNESS_VAL"
    write_state on "$BRIGHTNESS_VAL"
    notify_waybar
}

set_mode() {
    local m=$1
    if [[ "$m" = on ]]; then
        apply "$BRIGHTNESS_VAL"
    else
        apply 100
    fi
    BRIGHTNESS=$m
    write_state "$m" "$BRIGHTNESS_VAL"
    notify_waybar
}

case "${1:-status}" in
    status)
        if [[ "$BRIGHTNESS" = on ]]; then
            printf '%d%%\n' "$BRIGHTNESS_VAL"
        else
            printf 'off\n'
        fi
        ;;
    toggle)
        if [[ "$BRIGHTNESS" = on ]]; then set_mode off; else set_mode on; fi
        ;;
    increase) set_value $((BRIGHTNESS_VAL + STEP)) ;;
    decrease) set_value $((BRIGHTNESS_VAL - STEP)) ;;
    set) set_value "${2:?usage: $0 set <pct>}" ;;
    restore)
        if [[ "$BRIGHTNESS" = on ]]; then
            apply "$BRIGHTNESS_VAL"
        else
            apply 100
        fi
        ;;
    *)
        echo "usage: $0 [status|toggle|increase|decrease|set <pct>|restore]" >&2
        exit 1
        ;;
esac
