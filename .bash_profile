export GTK_IM_MODULE=xim
[[ -z $DISPLAY && $XDG_VTNR -eq 1 ]] && exec startx
