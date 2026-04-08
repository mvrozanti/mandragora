# =====================
# integrations.zsh — External tool integrations and sourced files
# fzf, zoxide, lf, ranger, conda, azure, travis, resty, etc.
# =====================

# zoxide
eval "$(zoxide init zsh)"

# Sourced config files
[ -f $HOME/.bash_aliases ] && source $HOME/.bash_aliases
[ -f $HOME/.cache/wal/sequences ] && cat $HOME/.cache/wal/sequences
[ -f $HOME/.travis/travis.sh ] && source $HOME/.travis/travis.sh
[ -f $HOME/.config/lf/lfcd.sh ] && source $HOME/.config/lf/lfcd.sh
[ -f ~/.local/bin/resty ] && . ~/.local/bin/resty
[ -f /opt/miniconda3/etc/profile.d/conda.sh ] && source /opt/miniconda3/etc/profile.d/conda.sh

# Google Cloud SDK
if [ -f '$HOME/Downloads/google-cloud-sdk/path.zsh.inc' ]; then . '$HOME/Downloads/google-cloud-sdk/path.zsh.inc'; fi
if [ -f '$HOME/Downloads/google-cloud-sdk/completion.zsh.inc' ]; then . '$HOME/Downloads/google-cloud-sdk/completion.zsh.inc'; fi

# Azure CLI
[ -f $HOME/azure-cli/bin ] && export PATH=$PATH:$HOME/azure-cli/bin && source '$HOME/azure-cli/az.completion'

# Powerlevel10k theme
POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(context dir vcs)
POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(status)
POWERLEVEL9K_SHORTEN_DIR_LENGTH=2
POWERLEVEL9K_SHORTEN_STRATEGY='truncate_middle'
POWERLEVEL9K_HOME_ICON=''
[ -f /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme ] && \
    source /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme
