# if [ -z "$SSH_AUTH_SOCK" ] ; then
#   eval `ssh-agent -s`
#   ssh-add
# fi
#eval `keychain --agents ssh --eval id_rsa`
# notify-send `last -20 -i|head -n +1|grep -v 0.0.0.0`
[[ -z $DISPLAY && $XDG_VTNR -eq 1 ]] && exec startx
