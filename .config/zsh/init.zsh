# =====================
# init.zsh — Main entry point
# Sources all zsh config modules in the correct order.
# To rollback: cp ~/.zshrc.backup ~/.zshrc && source ~/.zshrc
# =====================

export ZSH_CONFIG="$HOME/.config/zsh"

source $ZSH_CONFIG/settings.zsh
source $ZSH_CONFIG/plugins.zsh
source $ZSH_CONFIG/env.zsh
source $ZSH_CONFIG/functions.zsh
source $ZSH_CONFIG/zle.zsh
source $ZSH_CONFIG/bindings.zsh
source $ZSH_CONFIG/integrations.zsh
source $ZSH_CONFIG/aliases.zsh
source $ZSH_CONFIG/post-init.zsh
