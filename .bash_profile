# if [ -z "$SSH_AUTH_SOCK" ] ; then
#   eval `ssh-agent -s`
#   ssh-add
# fi
#eval `keychain --agents ssh --eval id_rsa`
[[ -z $DISPLAY && $XDG_VTNR -eq 1 ]] && exec startx
export JAVA_HOME=$(/usr/libexec/java_home -v 1.8)
