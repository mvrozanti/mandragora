#!/usr/bin/env bash
if [ $# -ne 2 ]; then
    echo "Usage: $0 <pid1> <pid2>"
    exit 1
fi

ptree1=$(pstree -p "$1")
if [[ "$ptree1" == *"$2"* ]]; then
    echo "Processes $1 and $2 are related"
else
    ptree2=$(pstree -p "$2")
    if [[ "$ptree2" == *"$1"* ]]; then
        echo "Processes $1 and $2 are related"
    else
        echo "Processes $1 and $2 are not related"
    fi
fi
