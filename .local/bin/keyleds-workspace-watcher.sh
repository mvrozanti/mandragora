#!/usr/bin/env bash
set -euo pipefail

DESKTOP_WS_ID="${KEYLEDS_DESKTOP_WS:-1}"
DBUS_DEST="org.etherdream.KeyledsService"
DBUS_PATH="/Service"
DBUS_IFACE="org.etherdream.keyleds.Service"

if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    echo "HYPRLAND_INSTANCE_SIGNATURE not set" >&2
    exit 1
fi

runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
sock2="$runtime_dir/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

set_workspace() {
    local id="$1"
    local value="other"
    if [ "$id" = "$DESKTOP_WS_ID" ]; then
        value="desktop"
    fi
    busctl --user call "$DBUS_DEST" "$DBUS_PATH" "$DBUS_IFACE" \
        setContextValue ss workspace "$value" >/dev/null 2>&1 || true
}

initial=$(hyprctl activeworkspace -j | jq -r '.id')
set_workspace "$initial"

exec socat -u "UNIX-CONNECT:$sock2" - | while IFS= read -r line; do
    case "$line" in
        workspace\>\>*|workspacev2\>\>*)
            payload="${line#*>>}"
            id="${payload%%,*}"
            set_workspace "$id"
            ;;
        focusedmon\>\>*|focusedmonv2\>\>*)
            payload="${line#*>>}"
            id="${payload##*,}"
            set_workspace "$id"
            ;;
    esac
done
