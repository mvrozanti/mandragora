xset r rate 200 30
setxkbmap us alt-intl
[[ -z $DISPLAY && $XDG_VTNR -eq 1 ]] && exec startx
