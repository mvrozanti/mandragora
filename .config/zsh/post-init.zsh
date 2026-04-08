# =====================
# post-init.zsh — Things that must load LAST
# tmux autostart, wal sequences, CURSOR_AGENT check
# =====================

# tmux autostart (must be at the very end so it doesn't block other config)
if [[ -n "$CURSOR_AGENT" ]]; then
    :
else
    if [ "$TMUX" = "" ]; then exec tmux; fi
fi
