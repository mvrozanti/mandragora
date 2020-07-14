# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH
# Path to your oh-my-zsh installation.
export ZSH=$HOME/.oh-my-zsh
ZSH_TMUX_AUTOSTART=true
ZSH_TMUX_FIXTERM=true
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=12'
ZSH_THEME="nexor"
# ZSH_THEME="powerlevel9k/powerlevel9k"
LS_COLORS='fi=0:ln=5:pi=0:so=7:bd=5:cd=5:or=31:mi=0:ex=93:*.py=36:di=40:*.zip=33:*.tgz=33:ow=1'
export HISTSIZE=1000000000
export SAVEHIST=$HISTSIZE
setopt EXTENDED_HISTORY

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion. Case
# sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment the following line to disable bi-weekly auto-update checks.
# DISABLE_AUTO_UPDATE="true"

# Uncomment the following line to change how often to auto-update (in days).
# export UPDATE_ZSH_DAYS=13

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction. lol wtf
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# The optional three formats: "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# HIST_STAMPS="dd.mm.yyyy"

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(rails git z)

source $ZSH/oh-my-zsh.sh

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
export EDITOR='nvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# ssh
export SSH_KEY_PATH="~/.ssh/rsa_id"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"
#
source ~/.oh-my-zsh/zsh-autosuggestions/zsh-autosuggestions.zsh
source $HOME/.bash_aliases
source $HOME/.ranger_aliases
stty -ixon

bindkey '^ ' autosuggest-accept
bindkey "\eOH" beginning-of-line
bindkey "\eOF" end-of-line
bindkey '\e[1~' beginning-of-line
bindkey '\e[4~' end-of-line
bindkey "\e[7~" beginning-of-line
bindkey "\e[8~" end-of-line
bindkey '^b' backward-word
bindkey '^f' forward-word
bindkey '^h' backward-delete-char
# bindkey '^l' delete-char
bindkey '^[^l' delete-word
run_ranger() { echo; ranger --choosedir=$HOME/.rangerdir < $TTY; LASTDIR=`cat $HOME/.rangerdir`; cd "$LASTDIR"; zle reset-prompt }
run_nnn() { echo; nnn < $TTY ; zle reset-prompt }
run_W() { clear; echo; W; zle reset-prompt }
run_weather() { clear; echo; weather; zle reset-prompt }
run_nvim_fast() { echo; nvim; zle reset-prompt }
run_nvim() { echo; nvim -c 'Startify'; zle reset-prompt }
run_khal() { echo; khal interactive < $TTY; zle reset-prompt }
cd_disk() { echo; cd ~/disk; zle reset-prompt }
cd_tcc() { echo; cd ~/mackenzie/TCC/; zle reset-prompt }
cd_sys4bank() { echo; cd ~/sys4bank/prog; zle reset-prompt }
cd_downloads() { echo; cd ~/Downloads; zle reset-prompt }
cd_fzf() { echo; cd "`exa -D|fzf`"; zle reset-prompt }
run_ncmpcpp() { BUFFER="ncmpcpp"; zle accept-line }
zle -N run_ranger
zle -N run_nnn
zle -N run_weather
zle -N run_W
zle -N run_nvim
zle -N run_nvim_fast
zle -N run_ncmpcpp
zle -N run_khal
zle -N cd_disk 
zle -N cd_tcc 
zle -N cd_sys4bank 
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
bindkey '^[d' 'cd_disk'
bindkey '^[D' 'cd_downloads'
bindkey '^[t' 'cd_tcc'
bindkey '^[s' 'cd_sys4bank'
bindkey '^f' 'cd_fzf'
bindkey -s '^[^M' '^M'

# vi - thanks hoberto
bindkey '\ek' up-history
bindkey '\ej' down-history

# rust
export PATH="$PATH:$HOME/.cargo/bin"

# rb
export PATH="$PATH:$HOME/.rvm/bin"
export GEM_HOME=$HOME/.gem
export PATH="$GEM_HOME/bin:$PATH"
export PATH="$PATH:$HOME/.gem/ruby/2.6.0/bin"

# js
export PATH=~/.npm/bin:$PATH

# go
export GOPATH=$HOME/go
export PATH=${GOPATH//://bin:}/bin:$PATH

# py
export PATH=~/.local/bin:$PATH

# vi_mode
# bindkey -v

# powerlevel9k
POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(dir vcs)
POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(status)
POWERLEVEL9K_SHORTEN_DIR_LENGTH=2
POWERLEVEL9K_SHORTEN_STRATEGY='truncate_middle'

POWERLEVEL9K_HOME_ICON='🏠'
source /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme

#   ctrl + u     : clear line
#   ctrl + w     : delete word backward
#   alt  + d     : delete word
#   ctrl + a     : move to beginning of line
#   ctrl + e     : move to end of line (e for end)
#   alt/ctrl + f : move to next word (f for forward)
#   alt/ctrl + b : move to previous word (b for backward)
#   ctrl + d     : delete char at current position (d for delete)
#   ctrl + k     : delete from character to end of line
#   alt  + .     : cycle through previous args

# source /usr/lib/python3.7/site-packages/powerline/bindings/bash/powerline.sh

# turn off beep
set bell-style none
# export PATH="$HOME/.pyenv/bin:$PATH"
# eval "$(pyenv init -)"
# eval "$(pyenv virtualenv-init -)"

VISUAL=nvim; export VISUAL EDITOR=nvim; export EDITOR

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
export MANPAGER="nvim +set\ filetype=man -"

cat $HOME/.cache/wal/sequences

if [[ ! $TERM =~ screen ]]; then
    exec tmux
fi

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/home/nexor/Downloads/google-cloud-sdk/path.zsh.inc' ]; then . '/home/nexor/Downloads/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/home/nexor/Downloads/google-cloud-sdk/completion.zsh.inc' ]; then . '/home/nexor/Downloads/google-cloud-sdk/completion.zsh.inc'; fi

export PATH="$HOME/.yarn/bin:$HOME/.config/yarn/global/node_modules/.bin:$PATH"

# dotnet
export PATH="$PATH:/home/nexor/.dotnet/tools"

export SYSTEMD_EDITOR=nvim

# added by travis gem
[ -f /home/nexor/.travis/travis.sh ] && source /home/nexor/.travis/travis.sh

[[ -f /home/nexor/azure-cli/bin ]] && export PATH=$PATH:/home/nexor/azure-cli/bin && source '/home/nexor/azure-cli/az.completion'

source /home/nexor/.config/lf/lfcd.sh

unsetopt hist_verify
