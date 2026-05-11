#!/usr/bin/env zsh
# Rofi wrapper to support zsh aliases, functions and commands.

# Generate the list of commands, aliases, and functions.
# We exclude internal functions starting with underscore.
LIST_CMD="zsh -i -c 'print -rl -- \${(k)commands} \${(k)aliases} \${(k)functions}' 2>/dev/null | grep -v '^_\| ' | sort -u"

exec rofi -show run \
    -run-list-command "$LIST_CMD" \
    -run-command "zsh -i -c '{cmd}'" \
    -run-shell-command "kitty -e zsh -i -c '{cmd}'"
