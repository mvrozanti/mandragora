#!/usr/bin/env bash
[[ "$1" =~ \.jpe?g$ ]] && convert "$1" png:- | wl-copy --type image/png || wl-copy --type image/png < "$1"
