export EDITOR='nvim'
export VISUAL='nvim'
export HISTSIZE=10000
export SAVEHIST=10000
setopt HIST_IGNORE_DUPS SHARE_HISTORY

export PATH="$HOME/.npm-global/bin:$PATH"
export npm_config_prefix="$HOME/.npm-global"

PROMPT='[%F{cyan}MANDRAGORA%f] %~ %# '

bindkey -e
bindkey '^?' backward-delete-char
bindkey '^H' backward-delete-char
bindkey '^[[3~' delete-char
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line
bindkey '^[[1~' beginning-of-line
bindkey '^[[4~' end-of-line
bindkey '^[[7~' beginning-of-line
bindkey '^[[8~' end-of-line
bindkey '^[[1;5C' forward-word
bindkey '^[[1;5D' backward-word

autoload -Uz compinit && compinit

[ -f ~/.bash_aliases ] && source ~/.bash_aliases
