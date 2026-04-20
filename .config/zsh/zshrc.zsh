# ── Extra Zsh Configuration ──────────────────────────────────────

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
bindkey '^[^l' delete-word
bindkey '^[^k' up-history
bindkey '^[^j' down-history

[ -f "$HOME/.config/lf/lfcd.sh" ] && source "$HOME/.config/lf/lfcd.sh"
[ -f "$HOME/.local/bin/resty" ] && source "$HOME/.local/bin/resty" >/dev/null 2>&1

eval "$(zoxide init zsh)"

[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
