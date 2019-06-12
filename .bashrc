POWERLINE_BASH_CONFIGURATION=1
POWERLINE_BASH_SELECT=1
. /usr/lib/python3.7/site-packages/powerline/bindings/bash/powerline.sh
[[ -f ~/.bash_aliases ]] && source ~/.bash_aliases
stty -ixon

[ -f ~/.fzf.bash ] && source ~/.fzf.bash

# added by travis gem
[ -f /home/nexor/.travis/travis.sh ] && source /home/nexor/.travis/travis.sh
