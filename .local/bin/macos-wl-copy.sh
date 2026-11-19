#!/usr/bin/env bash
text=()
while [ $# -gt 0 ]; do
  case "$1" in
    -t | --type | --seat)
      shift
      if [ $# -gt 0 ]; then shift; fi
      ;;
    -c | --clear)
      printf '' | /usr/bin/pbcopy
      exit 0
      ;;
    --)
      shift
      text+=("$@")
      break
      ;;
    -*) shift ;;
    *)
      text+=("$1")
      shift
      ;;
  esac
done

if [ ${#text[@]} -gt 0 ]; then
  printf '%s' "${text[*]}" | /usr/bin/pbcopy
else
  exec /usr/bin/pbcopy
fi
