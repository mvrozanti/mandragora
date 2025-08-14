#!/bin/bash

mapfile -t updates < <(checkupdates -n 2>/dev/null)
update_count=${#updates[@]}

if [ "$update_count" -eq 0 ]; then
    zenity --info --text="System is up to date!" --width=300
    exit 0
fi

zenity --question --text="$update_count package(s) available.\nDo you want to update?" --width=300
if [ $? -ne 0 ]; then exit 0; fi

PASSWORD=$(zenity --password --title="Enter your password")

if [ -z "$PASSWORD" ]; then
    zenity --error --text="No password entered. Exiting." --width=300
    exit 1
fi

echo "$PASSWORD" | sudo -S -v
if [ $? -ne 0 ]; then
    zenity --error --text="Authentication failed. Exiting." --width=300
    exit 1
fi

(
    total=$update_count
    current=0

    for line in "${updates[@]}"; do
        pkg=$(echo "$line" | awk '{print $1}')
        current=$((current+1))
        echo $((current * 100 / total))
        echo "# Installing $pkg"
        echo "$PASSWORD" | sudo -S pacman -Su --noconfirm "$pkg" >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "# Failed to install $pkg"
        fi
    done

    echo 100
    echo "# Update complete"
) | zenity --progress --title="Updating Packages" --auto-close --no-cancel --width=300

if [ $? -eq 0 ]; then
    zenity --info --text="Update complete!" --width=300
else
    zenity --error --text="Update canceled or failed." --width=300
fi

