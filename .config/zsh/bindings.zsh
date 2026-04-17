# =====================
# bindings.zsh — Key bindings (bindkey)
# Must come AFTER zle.zsh (widgets must be registered first)
# =====================

bindkey '^[r' 'run_lf'
bindkey '^[w' 'run_W'
bindkey '^[W' 'run_weather'
bindkey '^[v' 'run_nvim'
bindkey '^[V' 'run_nvim_fast'
bindkey '^[K' 'run_khal'
bindkey '^[D' 'cd_downloads'
bindkey '^f' 'cd_fzf'
bindkey '^[C' 'run_clock'
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
bindkey '^f' forward-word
bindkey '^w' forward-word
bindkey '^h' backward-delete-char
bindkey '^[^l' delete-word
bindkey '^[^k' up-history
bindkey '^[^j' down-history
bindkey '^k' increase-font
bindkey '^j' decrease-font
# bindkey '^[ ' accept-line
