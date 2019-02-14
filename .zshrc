# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH
# Path to your oh-my-zsh installation.
export ZSH=$HOME/.oh-my-zsh
ZSH_TMUX_AUTOSTART=true
ZSH_TMUX_FIXTERM=true
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=12'
ZSH_THEME="nexor"
LS_COLORS='fi=0:ln=5:pi=0:so=7:bd=5:cd=5:or=31:mi=0:ex=93:*.py=36:di=40:*.zip=33:*.tgz=33:ow=1'

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
plugins=(rails git zsh-autosuggestions z)

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
source /home/nexor/.ranger_aliases
# source /usr/lib/python3.7/site-packages/powerline/bindings/bash/powerline.sh
stty -ixon
unsetopt HIST_VERIFY
bindkey '^ ' autosuggest-accept
bindkey "\eOH" beginning-of-line
bindkey "\eOF" end-of-line
bindkey '\e[1~' beginning-of-line
bindkey '\e[4~' end-of-line
bindkey "\e[7~" beginning-of-line
bindkey "\e[8~" end-of-line

# vi - thanks hoberto
bindkey '\ek' up-history
bindkey '\ej' down-history

# rust
export PATH="$PATH:$HOME/.cargo/bin"

# rb
export PATH="$PATH:$HOME/.rvm/bin"
export GEM_HOME=$HOME/.gem

# js
export PATH=~/.npm/bin:$PATH

# go
export GOPATH=$HOME/go

# py
export PATH=~/.local/bin:$PATH
# source /usr/share/zsh-theme-powerlevel9k/powerlevel9k.zsh-theme

# turn off beep
set bell-style none
export PATH="/home/nexor/.pyenv/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"

VISUAL=nvim; export VISUAL EDITOR=nvim; export EDITOR

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
export MANPAGER="nvim +set\ filetype=man -"

cat /home/nexor/.cache/wal/sequences

if [[ ! $TERM =~ screen ]]; then
    exec tmux
fi

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/home/nexor/Downloads/google-cloud-sdk/path.zsh.inc' ]; then . '/home/nexor/Downloads/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/home/nexor/Downloads/google-cloud-sdk/completion.zsh.inc' ]; then . '/home/nexor/Downloads/google-cloud-sdk/completion.zsh.inc'; fi

export PATH="$HOME/.yarn/bin:$HOME/.config/yarn/global/node_modules/.bin:$PATH"
