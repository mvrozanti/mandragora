#!/usr/bin/env bash
sig=$(hypr-live-instance) || {
  echo "no live Hyprland instance to watch" >&2
  exit 1
}
sock="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/$sig/.socket2.sock"
socat -u "UNIX-CONNECT:$sock" STDOUT >/dev/null || true
sleep 3
[ "$(systemctl is-system-running 2>/dev/null || true)" = stopping ] && exit 0
systemctl --user is-active --quiet graphical-session.target || exit 0
echo "Hyprland IPC socket $sig closed while the session was still up" >&2
exit 1
