export EDITOR='nvim'
export VISUAL='nvim'
export HISTSIZE=10000
export SAVEHIST=10000
setopt HIST_IGNORE_DUPS SHARE_HISTORY

if [ -d /persist/npm-global ]; then
  export npm_config_prefix="/persist/npm-global"
  export PATH="/persist/npm-global/bin:$PATH"
else
  export npm_config_prefix="$HOME/.npm-global"
  export PATH="$HOME/.npm-global/bin:$PATH"
fi

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
