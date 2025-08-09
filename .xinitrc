#!/bin/sh
xrdb $HOME/.Xresources
xsetroot -cursor_name left_ptr
source /etc/X11/xinit/xinitrc.d/50-systemd-user.sh
xset s off
xset -dpms
xset s off -dpms
xset r rate 200 30
xset led named "Scroll Lock"
setxkbmap us alt-intl
xrandr -s 1920x1080@60
xmodmap ~/.Xmodmap
if ! pgrep -u "$USER" ssh-agent > /dev/null; then
    ssh-agent > ~/.ssh-agent-thing
fi
if [[ "$SSH_AGENT_PID" == "" ]]; then
    eval "$(<~/.ssh-agent-thing)"
fi
dbus-update-activation-environment DISPLAY XAUTHORITY
touch /tmp/sxhkd.fifo
xrandr --dpi 100
exec bspwm
