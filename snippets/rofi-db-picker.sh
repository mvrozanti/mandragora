#!/usr/bin/env bash
selected=$(printf 'MySQL Workbench\nMongoDB Compass\nBeekeeper Studio\nbaobab' | rofi -dmenu -p "Database")
case "$selected" in
    "MySQL Workbench")   mysql-workbench ;;
    "MongoDB Compass")   mongodb-compass ;;
    "Beekeeper Studio")  beekeeper-studio ;;
    baobab)              baobab ;;
esac
