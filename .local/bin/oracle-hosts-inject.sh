ip=$(cat /run/secrets/oracle/ip 2>/dev/null) || exit 0
[ -n "$ip" ] || exit 0
cp --remove-destination "$(readlink -f /etc/hosts)" /etc/hosts
sed -i '/[[:space:]]oracle$/d' /etc/hosts
printf '%s\toracle\n' "$ip" >> /etc/hosts
