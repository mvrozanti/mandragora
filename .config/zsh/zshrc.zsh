# ── Extra Zsh Configuration ──────────────────────────────────────

# Apply matugen terminal palette (skip inside tmux: OSC 11 forces an opaque
# pane background and breaks the terminal's transparency).
if [[ -z "$TMUX" ]]; then
  (cat ~/.cache/matugen/sequences 2>/dev/null &)
fi

# tmux autostart
if [[ -z "$TMUX" && -t 0 ]]; then exec tmux; fi

if [[ -n "$TMUX" && -n "$TMUX_PANE" ]]; then
  _tmux_publish_cwd() { tmux set -p -t "$TMUX_PANE" @cwd "$PWD" 2>/dev/null }
  typeset -ag precmd_functions
  precmd_functions+=(_tmux_publish_cwd)
fi

setopt AUTO_CD
setopt CORRECT
unsetopt HIST_VERIFY
setopt AUTO_MENU
setopt COMPLETE_IN_WORD
setopt ALWAYS_TO_END
setopt LIST_PACKED
setopt INTERACTIVE_COMMENTS

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' accept-exact-dirs true

stty -ixon

export PATH="$PATH:$HOME/.cargo/bin"
export PATH="$PATH:$HOME/.local/bin"
export PATH="$HOME/.yarn/bin:$HOME/.config/yarn/global/node_modules/.bin:$PATH"
export PATH="$HOME/.npm-global/bin:$PATH"

run_yazi() { y; zle send-break }
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

zle -N run_yazi
zle -N run_nvim
zle -N run_nvim_fast
zle -N run_khal
zle -N cd_downloads
zle -N cd_fzf
zle -N run_clock
zle -N run_gemini
zle -N zoxide_cd_interactive
zle -N zoxide_insert_path

bindkey '^[r' run_yazi
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
bindkey '\e[3~' delete-char
bindkey -M viins '\e[3~' delete-char
bindkey '^b' backward-word
bindkey '^w' forward-word
bindkey '^[[1;5D' backward-word
bindkey '^[[1;5C' forward-word
bindkey -M viins '^[[1;5D' backward-word
bindkey -M viins '^[[1;5C' forward-word
_exit-or-delete-char() {
  if [[ -z $BUFFER ]]; then
    exit
  else
    zle delete-char-or-list
  fi
}
zle -N _exit-or-delete-char
bindkey -M emacs '^D' _exit-or-delete-char
bindkey -M viins '^D' _exit-or-delete-char
bindkey '^h' backward-delete-char
zmodload zsh/complist
bindkey '^[[Z' reverse-menu-complete
bindkey -M menuselect '^[[Z' reverse-menu-complete
_backward-kill-word-punct() { local WORDCHARS=''; zle backward-kill-word }
_forward-kill-word-punct()  { local WORDCHARS=''; zle delete-word }
zle -N _backward-kill-word-punct
zle -N _forward-kill-word-punct
bindkey '^[[127;5u' _backward-kill-word-punct
bindkey '^[[127;3u' _backward-kill-word-punct
bindkey '^[^?'      _backward-kill-word-punct
bindkey '^H'        _backward-kill-word-punct
bindkey '^[^l'      _forward-kill-word-punct
bindkey '^[^k' up-history
bindkey '^[^j' down-history

run_nnn()     { echo; BUFFER="nnn -P p"; zle accept-line }
run_ncmpcpp() { echo; BUFFER="ncmpcpp"; zle accept-line }
zle -N run_nnn
zle -N run_ncmpcpp
bindkey '^[n' run_nnn
bindkey '^[w' run_ncmpcpp

c()   { wl-copy "$@" }
co()  { wl-paste "$@" }

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

[ -f "$HOME/.local/bin/resty" ] && source "$HOME/.local/bin/resty" >/dev/null 2>&1

eval "$(zoxide init zsh)"

# Alt+Enter inserts a literal newline (compose multi-line commands without \).
_mdg_alt_enter_newline() {
    LBUFFER+=$'\n'
    zle -R
}
zle -N _mdg_alt_enter_newline
bindkey -M emacs '^[^M' _mdg_alt_enter_newline
bindkey -M emacs '^[\r' _mdg_alt_enter_newline

[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# CircleCI personal token, decrypted by sops-nix (see modules/core/secrets.nix).
# Used by AI agents to consult CircleCI build status/logs without touching the
# encrypted file. Silent no-op if the secret isn't readable.
[[ -r /run/secrets/circleci/api_key ]] && export CIRCLECI_TOKEN="$(< /run/secrets/circleci/api_key)"

if [[ -r "$HOME/.config/path-exclusions" ]]; then
  typeset -ga _excluded_paths
  _excluded_paths=("${(@f)$(<"$HOME/.config/path-exclusions")}")
  _excluded_paths=("${_excluded_paths[@]/#\~/$HOME}")
  _excluded_paths=("${(@)_excluded_paths:#}")
  _resolved=()
  for _p in "${_excluded_paths[@]}"; do
    _r="$(readlink -f -- "$_p" 2>/dev/null)"
    [[ -n "$_r" && "$_r" != "$_p" ]] && _resolved+=("$_r")
  done
  _excluded_paths+=("${_resolved[@]}")
  unset _resolved _r _p
  if (( ${#_excluded_paths[@]} )); then
    _zo_excl=""
    for _p in "${_excluded_paths[@]}"; do
      _zo_excl+="${_p}:${_p}/*:"
    done
    export _ZO_EXCLUDE_DIRS="${_zo_excl%:}"
    unset _zo_excl _p

    zshaddhistory() {
      local cmd="$1" p
      for p in "${_excluded_paths[@]}"; do
        [[ "$cmd" == *"$p"* ]] && return 1
      done
      return 0
    }

    _path_excl_chpwd() {
      local p
      for p in "${_excluded_paths[@]}"; do
        if [[ "$PWD" == "$p"* ]]; then
          rm -f "$HOME/.cache/p10k-dump-m.zsh" "$HOME"/.cache/p10k-m/prompt-* 2>/dev/null
          return
        fi
      done
    }
    typeset -ag chpwd_functions
    chpwd_functions+=(_path_excl_chpwd)
  fi
fi
