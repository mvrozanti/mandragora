#!/usr/bin/env bash
AMOUNT=5
WHAT=paras
START=false

while getopts ":n:wpbls" opt; do
    case $opt in
        n) AMOUNT=$OPTARG ;;
        w) WHAT=words ;;
        p) WHAT=paras ;;
        b) WHAT=bytes ;;
        l) WHAT=lines ;;
        s) START=true ;;
    esac
done

curl -s -X POST https://lipsum.com/feed/json \
    -d "amount=$AMOUNT" -d "what=$WHAT" -d "start=$START" \
    | jq -r '.feed.lipsum'
