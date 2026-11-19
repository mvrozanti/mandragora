#!/usr/bin/env bash
args=()
while [ $# -gt 0 ]; do
  case "$1" in
    -u | -t | -i | -a | -c | -h | -r | --urgency | --expire-time | --icon | --app-name | --category | --hint | --replace-id)
      shift
      if [ $# -gt 0 ]; then shift; fi
      ;;
    -*) shift ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done

title="${args[0]:-}"
body="${args[1]:-}"

exec /usr/bin/osascript - "$title" "$body" <<'APPLESCRIPT'
on run argv
  display notification (item 2 of argv) with title (item 1 of argv)
end run
APPLESCRIPT
