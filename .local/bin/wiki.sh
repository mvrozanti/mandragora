#!/usr/bin/env bash
search="${*// /%20}"
inp=$(curl -s -H "Accept:application/json" "https://pt.wikipedia.org/w/api.php?action=opensearch&format=json&redirects=return&search=$search")
echo -e "Top 2 relevant searches\n"
for i in 0 1; do
    echo -e "\033[0;32m Title: \033[0;36m $(jq --argjson i "$i" '.[1][$i]' <<< "$inp")"
    echo -e "\033[0;32m About: \033[0;36m $(jq --argjson i "$i" '.[2][$i]' <<< "$inp")"
    echo -e "\033[0;32m Wiki Link: \033[0;36m $(jq --argjson i "$i" '.[3][$i]' <<< "$inp")\n"
done
echo -e "\033[0m"
