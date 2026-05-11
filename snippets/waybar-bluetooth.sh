#!/usr/bin/env bash
set -u

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/bluetooth-device"
FALLBACK_SINK="alsa_output.pci-0000_01_00.1.hdmi-stereo"

read_pinned_mac() {
    [[ -f "$CONFIG_FILE" ]] || return 1
    local mac
    mac=$(grep -m1 -oE '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' "$CONFIG_FILE") || return 1
    [[ -n "$mac" ]] && printf '%s' "${mac^^}"
}

first_paired_audio() {
    local line mac uuids
    while read -r _ mac _; do
        [[ -z "$mac" ]] && continue
        uuids=$(bluetoothctl info "$mac" 2>/dev/null | grep -E 'UUID:' || true)
        if grep -qE 'Audio Sink|Hands-Free|Headset' <<<"$uuids"; then
            printf '%s' "$mac"
            return 0
        fi
    done < <(bluetoothctl devices Paired 2>/dev/null)
    return 1
}

target_mac() {
    read_pinned_mac && return 0
    first_paired_audio && return 0
    return 1
}

is_connected() {
    bluetoothctl info "$1" 2>/dev/null | grep -q 'Connected: yes'
}

bt_sink_for() {
    local mac="$1"
    local node
    node=$(printf 'bluez_output.%s.1' "${mac//:/_}")
    if pactl list short sinks 2>/dev/null | awk '{print $2}' | grep -qx "$node"; then
        printf '%s' "$node"
        return 0
    fi
    pactl list short sinks 2>/dev/null | awk '{print $2}' | grep -E "^bluez_(output|sink)\.${mac//:/_}" | head -1
}

case "${1:-}" in
    toggle)
        mac=$(target_mac) || { exec blueman-manager; }
        if is_connected "$mac"; then
            bluetoothctl disconnect "$mac" >/dev/null 2>&1 || true
            pactl set-default-sink "$FALLBACK_SINK" >/dev/null 2>&1 || true
        else
            notify-send -t 2500 "Bluetooth" "Connecting $mac…" 2>/dev/null || true
            if bluetoothctl connect "$mac" >/dev/null 2>&1; then
                for _ in 1 2 3 4 5 6 7 8 9 10; do
                    sink=$(bt_sink_for "$mac")
                    [[ -n "$sink" ]] && break
                    sleep 0.3
                done
                if [[ -n "${sink:-}" ]]; then
                    pactl set-default-sink "$sink" >/dev/null 2>&1 || true
                    pactl list short sink-inputs 2>/dev/null | awk '{print $1}' | while read -r id; do
                        pactl move-sink-input "$id" "$sink" >/dev/null 2>&1 || true
                    done
                    notify-send -t 2000 "Bluetooth" "Connected → $sink" 2>/dev/null || true
                else
                    notify-send -u critical -t 3000 "Bluetooth" "Connected but no audio sink appeared" 2>/dev/null || true
                fi
            else
                notify-send -u critical -t 3000 "Bluetooth" "Failed to connect $mac" 2>/dev/null || true
            fi
        fi
        ;;
    pair|"")
        exec blueman-manager
        ;;
    *)
        echo "usage: $0 {toggle|pair}" >&2
        exit 2
        ;;
esac
