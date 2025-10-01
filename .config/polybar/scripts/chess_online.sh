#!/usr/bin/env bash
u="$(base64 -d <<< cmlja2VlZW5ubg==)"
icon=""
color_online="%{F#00FF00}"
color_offline="%{F#FFFFFF}"
underline_online="%{u#00FF00}"
underline_offline="%{u#FFFFFF}"

last_online=$(curl -s https://api.chess.com/pub/player/$u | jq .last_online)
now=$(date +%s)
diff=$((now - last_online))

if [ "$diff" -lt 5 ]; then
    notify-send "Chess.com" "$u is online now!"
    echo "${underline_online}${color_online}${icon}%{u-}%{F-}"
else
    echo "${color_offline}${icon}%{F-}"
fi

