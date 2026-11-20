#!/usr/bin/env bash
selected=$(printf 'VSCode\nIntelliJ\nPyCharm\nCursor' | vicinae dmenu -p "IDE")
case "$selected" in
    VSCode)    code ;;
    IntelliJ)  idea-ultimate ;;
    PyCharm)   pycharm-professional ;;
    Cursor)    cursor ;;
esac
