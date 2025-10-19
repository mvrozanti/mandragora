#!/bin/sh

if ! updates=$(checkupdates 2> /dev/null | wc -l ); then
    updates=0
fi

if [ "$updates" -gt 600 ]; then
    echo "%{u#f00} $updates "
elif [ "$updates" -gt 400 ]; then
    echo "%{u#ff0} $updates "
elif [ "$updates" -gt 0 ]; then
    echo " $updates "
else
    echo ""
fi
