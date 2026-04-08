# =====================
# env.zsh — Environment variables, PATH, exports
# =====================

# Editors and browser
export EDITOR='nvim'
export VISUAL=nvim
export BROWSER=firefox

# SSH
export SSH_KEY_PATH="~/.ssh/rsa_id"

# PATH additions
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
export PATH="$HOME/.yarn/bin:$HOME/.config/yarn/global/node_modules/.bin:$PATH"
export PATH="$HOME/.npm-global/bin:$PATH"
export PATH="$PATH:$HOME/.dotnet/tools"

# Perl (local::lib)
PATH="/home/m/perl5/bin${PATH:+:${PATH}}"; export PATH;
PERL5LIB="/home/m/perl5/lib/perl5${PERL5LIB:+:${PERL5LIB}}"; export PERL5LIB;
PERL_LOCAL_LIB_ROOT="/home/m/perl5${PERL_LOCAL_LIB_ROOT:+:${PERL_LOCAL_LIB_ROOT}}"; export PERL_LOCAL_LIB_ROOT;
PERL_MB_OPT="--install_base \"/home/m/perl5\""; export PERL_MB_OPT;
PERL_MM_OPT="INSTALL_BASE=/home/m/perl5"; export PERL_MM_OPT;

# Systemd editor
export SYSTEMD_EDITOR=nvim

# Man pager
export MANPAGER="nvim +Man!"

# Cows
export COWPATH="/usr/share/cows"
if [ -d "$HOME/.config/cowfiles" ] ; then
    COWPATH="$COWPATH:$HOME/.config/cowfiles"
fi

# Python
export PYTHONSTARTUP="$HOME/.pythonrc"
export NODE_PATH=/usr/lib/node_modules/

# Default user (for prompt)
DEFAULT_USER=$USER
