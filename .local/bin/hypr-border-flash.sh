#!/usr/bin/env bash

handle() {
  case $1 in
    activewindowv2*)
      hyprctl --batch "keyword general:col.active_border \$color1 \$color2 45deg; keyword general:col.active_border rgba(00000000)"
      ;;
  esac
}

socat -U - "UNIX-CONNECT:\$XDG_RUNTIME_DIR/hypr/\$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" | while read -r line; do
  handle "\$line"
done
