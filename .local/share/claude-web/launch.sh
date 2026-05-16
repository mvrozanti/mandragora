#!/usr/bin/env bash
set -euo pipefail

HOME_DIR="${HOME:-/home/m}"

resolve_dir() {
  local raw="$1"
  case "$raw" in
    "~")    raw="$HOME_DIR" ;;
    "~/"*)  raw="$HOME_DIR/${raw#~/}" ;;
  esac
  realpath -m -- "$raw" 2>/dev/null || printf '%s\n' "$raw"
}

pick_dir() {
  local cur="$1"
  while true; do
    local out key item
    out=$(
      {
        printf '%s\n' "▸ open this directory"
        [ "$cur" != "/" ] && printf '%s\n' "↑ .."
        find "$cur" -mindepth 1 -maxdepth 1 -type d \
          ! -name '.git' ! -name 'node_modules' ! -name '__pycache__' \
          ! -name '.venv' ! -name '.direnv' \
          -printf '  %f\n' 2>/dev/null | sort -f
      } | fzf \
          --ansi \
          --height=100% \
          --reverse \
          --pointer='▌' \
          --marker=' ' \
          --color='hl:#7aa2f7,hl+:#7dcfff,pointer:#bb9af7,header:#9ece6a,prompt:#7dcfff,info:#565f89,border:#3b4261' \
          --border=rounded \
          --header=$'📂 '"$cur"$'\n\nEnter = descend or open · Alt-Enter = open current · Esc = quit' \
          --prompt='filter ▸ ' \
          --preview-window='right:55%:wrap:border-left' \
          --preview="$0 __preview $cur {}" \
          --expect=alt-enter
    ) || return 130

    key=$(printf '%s' "$out" | sed -n '1p')
    item=$(printf '%s' "$out" | sed -n '2p')
    item="${item#  }"

    if [ "$key" = "alt-enter" ]; then
      printf '%s\n' "$cur"
      return 0
    fi

    case "$item" in
      "▸ open this directory") printf '%s\n' "$cur"; return 0 ;;
      "↑ ..")                  cur=$(dirname -- "$cur") ;;
      "")                      printf '%s\n' "$cur"; return 0 ;;
      *)                       cur="${cur%/}/$item" ;;
    esac
  done
}

preview() {
  local cur="$1" entry="${2:-}"
  entry="${entry#  }"
  case "$entry" in
    "▸ open this directory")
      printf 'will launch claude in:\n  %s\n' "$cur"
      ;;
    "↑ ..")
      printf 'will go up to:\n  %s\n' "$(dirname -- "$cur")"
      ;;
    "")
      ls -lah --color=always -- "$cur" 2>/dev/null | head -80
      ;;
    *)
      local target="$cur/$entry"
      printf '%s\n\n' "$target"
      if [ -d "$target/.git" ]; then
        local branch
        branch=$(git -C "$target" symbolic-ref --short HEAD 2>/dev/null || git -C "$target" rev-parse --short HEAD 2>/dev/null || true)
        [ -n "$branch" ] && printf 'git: %s\n\n' "$branch"
      fi
      ls -lah --color=always -- "$target" 2>/dev/null | head -80
      ;;
  esac
}

if [ "${1:-}" = "__preview" ]; then
  shift
  preview "$@"
  exit 0
fi

start="${1:-}"
if [ -n "$start" ]; then
  chosen=$(resolve_dir "$start")
  if [ ! -d "$chosen" ]; then
    printf '\033[31m%s is not a directory\033[0m\n' "$chosen" >&2
    printf 'falling back to picker rooted at %s\n\n' "$HOME_DIR" >&2
    sleep 1
    chosen=$(pick_dir "$HOME_DIR") || exit 130
  fi
else
  chosen=$(pick_dir "$HOME_DIR") || exit 130
fi

slug=$(printf '%s' "$chosen" | sha1sum | cut -c1-10)
session="claude-${slug}"

clear
printf '\033[1;36mopening claude in:\033[0m %s\n' "$chosen"
printf '\033[2mtmux session:\033[0m %s\n\n' "$session"

cd -- "$chosen" || { printf 'cd failed\n' >&2; exit 1; }
exec tmux new-session -A -s "$session" -c "$chosen" claude
