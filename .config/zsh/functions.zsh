# =====================
# functions.zsh — ZLE widget functions
# Must be defined BEFORE zle -N registration
# =====================

run_ranger() { echo; ranger --choosedir=$HOME/.rangerdir < $TTY; LASTDIR=`cat $HOME/.rangerdir`; cd "$LASTDIR"; zle reset-prompt }
run_nvim_fast() { echo; nvim; zle reset-prompt }
run_nvim() { echo; nvim; zle reset-prompt }
run_nnn() { echo; BUFFER="nnn -P p"; zle accept-line }
run_lf() { lf; zle send-break }
run_khal() { echo; khal interactive < $TTY; zle reset-prompt }
cd_downloads() { echo; cd ~/Downloads; zle reset-prompt }
cd_fzf() { echo; cd "`ls|fzf`"; zle reset-prompt }
run_ncmpcpp() { BUFFER="ncmpcpp"; zle accept-line }
run_clock() { echo; peaclock; zle reset-prompt}
run_gemini() { echo; gemini </dev/tty; zle reset-prompt }
run_zoxide_query() { echo; zoxide query -i </dev/tty; zle reset-prompt }

function increase-font() {
  xdotool key ctrl+shift+equal
}
function decrease-font() {
  xdotool key ctrl+minus
}

# NVM lazy loading
export NVM_DIR="$HOME/.nvm"
lazynvm() {
  unset -f nvm node npm npx
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
}

nvm() { lazynvm; nvm "$@"; }
node() { lazynvm; node "$@"; }
npm() { lazynvm; npm "$@"; }
npx() { lazynvm; npx "$@"; }
