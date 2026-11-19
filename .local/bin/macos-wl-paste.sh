#!/usr/bin/env bash
type=""
while [ $# -gt 0 ]; do
  case "$1" in
    -t | --type)
      shift
      type="${1:-}"
      if [ $# -gt 0 ]; then shift; fi
      ;;
    --type=*)
      type="${1#--type=}"
      shift
      ;;
    *) shift ;;
  esac
done

case "$type" in
  image/*) exec pngpaste - ;;
  *) exec /usr/bin/pbpaste ;;
esac
