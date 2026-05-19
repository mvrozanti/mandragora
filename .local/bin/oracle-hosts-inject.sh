[ -r /run/secrets/oracle/ip ] || exit 0
ip=$(</run/secrets/oracle/ip)
[ -n "$ip" ] || exit 0
cp --remove-destination "$(readlink -f /etc/hosts)" /etc/hosts
sed -i '/[[:space:]]oracle$/d' /etc/hosts
printf '%s\toracle\n' "$ip" >> /etc/hosts
