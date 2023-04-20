export ZSH=$HOME/.oh-my-zsh
ZSH_TMUX_AUTOSTART=true
ZSH_TMUX_FIXTERM=true
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=12'
eval "$(dircolors -p | \
    sed 's/ 4[0-9];/ 01;/; s/;4[0-9];/;01;/g; s/;4[0-9] /;01 /' | \
    dircolors /dev/stdin)"
export HISTSIZE=1000000000
export SAVEHIST=$HISTSIZE
setopt EXTENDED_HISTORY
plugins=(rails z zsh-syntax-highlighting)
source $ZSH/oh-my-zsh.sh
export EDITOR='nvim'
export SSH_KEY_PATH="~/.ssh/rsa_id"

[ -f ~/.oh-my-zsh/zsh-autosuggestions/zsh-autosuggestions.zsh ] && source ~/.oh-my-zsh/zsh-autosuggestions/zsh-autosuggestions.zsh
[ -f $HOME/.bash_aliases ] && source $HOME/.bash_aliases
[ -f $HOME/.ranger_aliases ] && source $HOME/.ranger_aliases
stty -ixon

bindkey '^ ' autosuggest-accept
bindkey '\eOH' beginning-of-line
bindkey '\eOF' end-of-line
bindkey '\e[1~' beginning-of-line
bindkey '\e[4~' end-of-line
bindkey '\e[7~' beginning-of-line
bindkey '\e[8~' end-of-line
bindkey '^b' backward-word
bindkey '^f' forward-word
bindkey '^h' backward-delete-char
bindkey '^[^l' delete-word
bindkey '^[^k' up-history
bindkey '^[^j' down-history

run_ranger() { echo; ranger --choosedir=$HOME/.rangerdir < $TTY; LASTDIR=`cat $HOME/.rangerdir`; cd "$LASTDIR"; zle reset-prompt }
run_lf() { echo; lf; zle reset-prompt }
run_nnn() { echo; nnn < $TTY ; zle reset-prompt }
run_W() { clear; echo; W; zle reset-prompt }
run_weather() { clear; echo; weather; zle reset-prompt }
run_nvim_fast() { echo; nvim; zle reset-prompt }
run_nvim() { echo; nvim -c 'Startify'; zle reset-prompt }
run_khal() { echo; khal interactive < $TTY; zle reset-prompt }
cd_tcc() { echo; cd ~/mackenzie/TCC/; zle reset-prompt }
cd_sys4bank() { echo; cd ~/sys4bank/prog; zle reset-prompt }
cd_downloads() { echo; cd ~/Downloads; zle reset-prompt }
cd_fzf() { echo; cd "`ls|fzf`"; zle reset-prompt }
run_ncmpcpp() { BUFFER="ncmpcpp"; zle accept-line }
run_clock() { echo; peaclock; zle reset-prompt}

zle -N run_clock
zle -N run_ranger

zle -N run_nnn
zle -N run_weather
zle -N run_W
zle -N run_nvim
zle -N run_nvim_fast
zle -N run_ncmpcpp
zle -N run_khal
zle -N cd_tcc 
zle -N cd_downloads 
zle -N cd_fzf 

bindkey '^[R' 'run_nnn'
bindkey '^[r' 'run_ranger'

bindkey '^[w' 'run_W'
bindkey '^[W' 'run_weather'
bindkey '^[v' 'run_nvim'
bindkey '^[V' 'run_nvim_fast'
bindkey '^[m' 'run_ncmpcpp'
bindkey '^[K' 'run_khal'
bindkey '^[D' 'cd_downloads'
bindkey '^[t' 'cd_tcc'
bindkey '^f' 'cd_fzf'
bindkey '^[C' 'run_clock'
bindkey -s '^[^M' '^M'

autoload -Uz increase-font
autoload -Uz decrease-font
function increase-font() {
  xdotool key ctrl+shift+equal
}
function decrease-font() {
  xdotool key ctrl+minus
}

zle -N increase-font
zle -N decrease-font
bindkey '^k' increase-font
bindkey '^j' decrease-font

export PATH="$PATH:$HOME/.cargo/bin"
export PATH="$PATH:$HOME/.rvm/bin"
export GEM_HOME=$HOME/.gem
export PATH="$GEM_HOME/bin:$PATH"
export PATH="$PATH:$HOME/.gem/ruby/2.6.0/bin"
export PATH="$PATH:$HOME/.gem/ruby/2.7.0/bin"
export PATH=~/.npm/bin:$PATH
export GOPATH=$HOME/go
export PATH=${GOPATH//://bin:}/bin:$PATH
export PATH=~/.local/bin:$PATH

POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(context dir vcs)
POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(status)
POWERLEVEL9K_SHORTEN_DIR_LENGTH=2
POWERLEVEL9K_SHORTEN_STRATEGY='truncate_middle'

DEFAULT_USER=$USER

POWERLEVEL9K_HOME_ICON=''

[ -f /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme ] && \
    source /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme
[ -f ~/.oh-my-zsh/custom/themes/powerlevel10k/powerlevel10k.zsh-theme ] && \
    source ~/.oh-my-zsh/custom/themes/powerlevel10k/powerlevel10k.zsh-theme 
set bell-style none
VISUAL=nvim; export VISUAL 
EDITOR=nvim; export EDITOR
BROWSER=firefox; export BROWSER

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
export MANPAGER="nvim +Man!"

[ -f $HOME/.cache/wal/sequences ] && cat $HOME/.cache/wal/sequences

if [ "$TMUX" = "" ]; then exec tmux; fi

if [ -f '$HOME/Downloads/google-cloud-sdk/path.zsh.inc' ]; then . '$HOME/Downloads/google-cloud-sdk/path.zsh.inc'; fi

if [ -f '$HOME/Downloads/google-cloud-sdk/completion.zsh.inc' ]; then . '$HOME/Downloads/google-cloud-sdk/completion.zsh.inc'; fi

export PATH="$HOME/.yarn/bin:$HOME/.config/yarn/global/node_modules/.bin:$PATH"

export PATH="$PATH:$HOME/.dotnet/tools"

export SYSTEMD_EDITOR=nvim

[ -f $HOME/.travis/travis.sh ] && source $HOME/.travis/travis.sh

[ -f $HOME/azure-cli/bin ] && export PATH=$PATH:$HOME/azure-cli/bin && source '$HOME/azure-cli/az.completion'

[ -f $HOME/.config/lf/lfcd.sh ] && source $HOME/.config/lf/lfcd.sh

unsetopt hist_verify
export COWPATH="/usr/share/cows"
if [ -d "$HOME/.config/cowfiles" ] ; then
    COWPATH="$COWPATH:$HOME/.config/cowfiles"
fi
PATH="/home/m/perl5/bin${PATH:+:${PATH}}"; export PATH;
PERL5LIB="/home/m/perl5/lib/perl5${PERL5LIB:+:${PERL5LIB}}"; export PERL5LIB;
PERL_LOCAL_LIB_ROOT="/home/m/perl5${PERL_LOCAL_LIB_ROOT:+:${PERL_LOCAL_LIB_ROOT}}"; export PERL_LOCAL_LIB_ROOT;
PERL_MB_OPT="--install_base \"/home/m/perl5\""; export PERL_MB_OPT;
PERL_MM_OPT="INSTALL_BASE=/home/m/perl5"; export PERL_MM_OPT;
[ -f ~/.local/bin/resty ] && . ~/.local/bin/resty
export PYTHONSTARTUP="$HOME/.pythonrc"
source /usr/share/autojump/autojump.zsh
