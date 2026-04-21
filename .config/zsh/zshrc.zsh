# ── Extra Zsh Configuration ──────────────────────────────────────

printf '\e[1 q'

# tmux autostart
if [[ -z "$TMUX" && -t 0 ]]; then exec tmux; fi

setopt AUTO_CD
setopt CORRECT
setopt HIST_VERIFY

stty -ixon

export PATH="$PATH:$HOME/.cargo/bin"
export PATH="$PATH:$HOME/.local/bin"
export GOPATH="$HOME/go"
export PATH="${GOPATH//://bin:}/bin:$PATH"
export PATH="$HOME/.yarn/bin:$HOME/.config/yarn/global/node_modules/.bin:$PATH"
export PATH="$HOME/.npm-global/bin:$PATH"

run_lf() { lf; zle send-break }
run_nvim() { echo; nvim; zle reset-prompt }
run_nvim_fast() { echo; nvim; zle reset-prompt }
run_khal() { echo; khal interactive < $TTY; zle reset-prompt }
cd_downloads() { echo; cd ~/Downloads; zle reset-prompt }
cd_fzf() { echo; cd "$(ls | fzf)"; zle reset-prompt }
run_clock() { echo; peaclock; zle reset-prompt }
run_gemini() { echo; gemini </dev/tty; zle reset-prompt }

zoxide_cd_interactive() {
  local dir
  dir=$(zoxide query -i 2>/dev/tty)
  if [[ -n "$dir" ]]; then
    cd "$dir"
    zle reset-prompt
    zle redisplay
  fi
}

zoxide_insert_path() {
  local dir
  dir=$(zoxide query -i 2>/dev/tty)
  if [[ -n "$dir" ]]; then
    LBUFFER+="${(q)dir}"
    zle redisplay
  fi
}

zle -N run_lf
zle -N run_nvim
zle -N run_nvim_fast
zle -N run_khal
zle -N cd_downloads
zle -N cd_fzf
zle -N run_clock
zle -N run_gemini
zle -N zoxide_cd_interactive
zle -N zoxide_insert_path

bindkey '^[r' run_lf
bindkey '^[v' run_nvim
bindkey '^[V' run_nvim_fast
bindkey '^[K' run_khal
bindkey '^[D' cd_downloads
bindkey '^f' cd_fzf
bindkey '^[C' run_clock
bindkey '^[g' run_gemini
bindkey '\ek' up-history
bindkey '\ej' down-history
bindkey '^[;' zoxide_cd_interactive
bindkey '^[,' zoxide_insert_path
bindkey '^ ' autosuggest-accept
bindkey '\eOH' beginning-of-line
bindkey '\eOF' end-of-line
bindkey '\e[1~' beginning-of-line
bindkey '\e[4~' end-of-line
bindkey '\e[7~' beginning-of-line
bindkey '\e[8~' end-of-line
bindkey '^b' backward-word
bindkey '^w' forward-word
bindkey '^h' backward-delete-char
bindkey '^[[127;5u' backward-kill-word
bindkey '^[[127;3u' backward-kill-word
bindkey '^[^?' backward-kill-word
bindkey '^H' backward-kill-word
bindkey '^[^l' delete-word
bindkey '^[^k' up-history
bindkey '^[^j' down-history

run_nnn()     { echo; BUFFER="nnn -P p"; zle accept-line }
run_ncmpcpp() { echo; BUFFER="ncmpcpp"; zle accept-line }
zle -N run_nnn
zle -N run_ncmpcpp
bindkey '^[n' run_nnn
bindkey '^[w' run_ncmpcpp

c()   { wl-copy }
co()  { wl-paste }
cov() { nvim "$(co)" }

pa()  { ps aux | grep -v grep | grep -i "${1:-.}" }
eip() { curl -s ipinfo.io | jq -r '.ip' }
lip() { ip a | grep 192 | cut -d' ' -f6 | sed 's/\(.*\)\/.*/\1/g' }

K() {
  local selected
  selected=$(pa "$@" | awk '{printf("%s ",$2);for(i=11;i<=NF;++i){printf("%s ",$i)};print("")}' \
    | fzf -m --header='[kill] TAB=multi' --preview 'echo {}' --preview-window=down:3:wrap)
  [[ -n "$selected" ]] && echo "$selected" | awk '{print $1}' | xargs -r kill
}
K9() {
  local selected
  selected=$(pa "$@" | awk '{printf("%s ",$2);for(i=11;i<=NF;++i){printf("%s ",$i)};print("")}' \
    | fzf -m --header='[kill -9] TAB=multi' --preview 'echo {}' --preview-window=down:3:wrap)
  [[ -n "$selected" ]] && echo "$selected" | awk '{print $1}' | xargs -r kill -9
}
k() {
  if [[ $# -eq 0 ]]; then K
  elif [[ "$1" =~ ^[0-9]+$ ]]; then kill "$1"
  else pkill -i -f "$@"
  fi
}

P()   { curl -sF "file=@-" https://0x0.st }
gr()  { git checkout $(git rev-list -n 1 HEAD -- "$@")~1 -- "$@" }
gdc() { git diff HEAD HEAD~1 }

lf() {
  local pane_id last_dir
  pane_id=$(tmux display-message -p '#{pane_id}' 2>/dev/null)
  [ -n "$pane_id" ] && export LF_TMUX_PANE="$pane_id"
  last_dir=$(lf-ueberzug -print-last-dir "$@")
  unset LF_TMUX_PANE 2>/dev/null
  [ -n "$last_dir" ] && builtin cd "$last_dir"
}
[ -f "$HOME/.local/bin/resty" ] && source "$HOME/.local/bin/resty" >/dev/null 2>&1

eval "$(zoxide init zsh)"

[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
