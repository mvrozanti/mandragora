# ── Extra Zsh Configuration ──────────────────────────────────────

setopt AUTO_CD
setopt CORRECT
setopt HIST_VERIFY

stty -ixon

run_lf() { 
    lf
    zle send-break 
}
zle -N run_lf
bindkey '^[r' run_lf
bindkey '^ ' autosuggest-accept

[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
