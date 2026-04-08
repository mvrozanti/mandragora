# =====================
# settings.zsh — Zsh options, history, completion settings
# Must load BEFORE plugins.zsh sources oh-my-zsh.sh
# =====================

export ZSH=$HOME/.oh-my-zsh

# OMZ settings (must be set before sourcing oh-my-zsh.sh)
ZSH_TMUX_AUTOSTART=true
ZSH_TMUX_FIXTERM=true
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=12'
ZSH_DISABLE_COMPFIX="true"
DISABLE_AUTO_UPDATE="true"
DISABLE_UPDATE_PROMPT="true"

# History
export HISTSIZE=1000000000
export SAVEHIST=$HISTSIZE
setopt EXTENDED_HISTORY

# dircolors with adjusted colors
eval "$(dircolors -p | \
    sed 's/ 4[0-9];/ 01;/; s/;4[0-9];/;01;/g; s/;4[0-9] /;01 /' | \
    dircolors /dev/stdin)"

# Completion settings
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path ~/.zsh/cache
zstyle ':completion:*' accept-exact-dirs true

# Bell and misc settings
set bell-style none
unsetopt hist_verify
