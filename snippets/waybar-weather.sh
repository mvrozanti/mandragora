#!/usr/bin/env bash
get_icon() {
  case $1 in
    01d) echo "" ;; 01n) echo "" ;;
    02d) echo "" ;; 02n) echo "" ;;
    03*)  echo "" ;; 04*)  echo "" ;;
    09d) echo "" ;; 09n) echo "" ;;
    10d) echo "" ;; 10n) echo "" ;;
    11d) echo "" ;; 11n) echo "" ;;
    13d) echo "" ;; 13n) echo "" ;;
    50d) echo "" ;; 50n) echo "" ;;
    *)    echo "" ;;
  esac
}

KEY="$OPEN_WEATHER_MAP_KEY"
CITY="3448439"
UNITS="metric"

API="https://api.openweathermap.org/data/2.5"

if [[ -z "$KEY" ]]; then
  exit 0
fi

if [[ -n "$CITY" ]]; then
  weather=$(curl -sf "$API/weather?appid=$KEY&id=$CITY&units=$UNITS")
else
  location=$(curl -sf "https://location.services.mozilla.com/v1/geolocate?key=geoclue")
  [[ -z "$location" ]] && exit 0
  lat=$(echo "$location" | jq '.location.lat')
  lon=$(echo "$location" | jq '.location.lng')
  weather=$(curl -sf "$API/weather?appid=$KEY&lat=$lat&lon=$lon&units=$UNITS")
fi

[[ -z "$weather" ]] && exit 0

temp=$(echo "$weather" | jq ".main.temp" | cut -d "." -f 1)
icon_code=$(echo "$weather" | jq -r ".weather[0].icon")
desc=$(echo "$weather" | jq -r ".weather[0].description")
icon=$(get_icon "$icon_code")

printf '{"text": "%s %s°C", "tooltip": "%s"}\n' "$icon" "$temp" "$desc"
