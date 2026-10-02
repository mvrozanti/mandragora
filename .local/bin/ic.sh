#!/usr/bin/env bash
mime=$(file --mime-type -b "$1" | cut -d';' -f1)
if [ "$mime" = image/gif ]; then
  python3 -c 'import os,sys,urllib.parse;print("file://"+urllib.parse.quote(os.path.realpath(sys.argv[1]),safe="/"))' "$1" | wl-copy --type text/uri-list
elif [ "$mime" = image/jpeg ]; then
  convert "$1" png:- | wl-copy --type image/png
else
  wl-copy < "$1"
fi
