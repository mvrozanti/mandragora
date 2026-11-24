#!/usr/bin/env bash
deadline=$(date -d "$MEME_NIGHTLY_UNTIL" +%s)
left=$(( deadline - $(date +%s) ))

if (( left < 600 )); then
  echo "meme-nightly: less than 10 min left before $MEME_NIGHTLY_UNTIL, not starting"
  exit 0
fi

timeout -s INT -k 120 "$left" meme tag --untagged || echo "meme-nightly: meme tag stopped with status $?"
