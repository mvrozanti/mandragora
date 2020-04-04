#!/bin/bash

sync_output=`mbsync -V hotmail`
ps aux | grep /usr/local/bin/dota && exit 0
slave_count=`grep 'Inbox' -A6 <<< $sync_output | grep -E '^slave' | cut -d',' -f1 | tr -cd '[[:digit:]]'`
master_count=`grep 'Inbox' -A6 <<< $sync_output | grep -E '^master' | cut -d',' -f1 | tr -cd '[[:digit:]]'`
new_mail_count=$(($master_count - $slave_count))
echo $new_mail_count
if [[ $new_mail_count -gt 2 ]]; then
  notify-send "
  You have $new_mail_count new emails."
elif [[ $new_mail_count -eq 1 ]]; then
  notify-send "
  You have $new_mail_count new email."
fi

