#!/bin/sh
# Helper script for tmux split-window from lf
# Arguments: $1 = pane_id, $2 = pane_tty, $3 = pane_current_path, $4 = split_direction (-h or -v)

PANE_ID="$1"
PANE_TTY="$2"
PANE_CWD="$3"
DIRECTION="$4"

SYNC_FILE="$HOME/.cache/lf/cwd_$PANE_ID"

# Check if lf is running on this TTY
if pgrep -t "$PANE_TTY" lf >/dev/null && [ -f "$SYNC_FILE" ]; then
    TARGET_DIR=$(cat "$SYNC_FILE")
    if [ -d "$TARGET_DIR" ]; then
        tmux split-window "$DIRECTION" -c "$TARGET_DIR"
        exit 0
    fi
fi

# Fallback
tmux split-window "$DIRECTION" -c "$PANE_CWD"
