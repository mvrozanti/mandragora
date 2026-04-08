# =====================
# plugins.zsh — Oh My Zsh and plugin loading
# Sources OMZ and all plugin files
# =====================

# OMZ plugins list (must be set before sourcing oh-my-zsh.sh)
plugins=(zsh-syntax-highlighting)

# Source Oh My Zsh
source $ZSH/oh-my-zsh.sh

# Plugins sourced after OMZ
[ -f ~/.oh-my-zsh/zsh-autosuggestions/zsh-autosuggestions.zsh ] && source ~/.oh-my-zsh/zsh-autosuggestions/zsh-autosuggestions.zsh
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Stty fix (must be after OMZ)
[[ -t 0 ]] && stty -ixon
