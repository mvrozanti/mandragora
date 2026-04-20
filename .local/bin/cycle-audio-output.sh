#!/usr/bin/env bash
sinks=($(pactl list short sinks | awk '{print $2}'))
current=$(pactl info | grep "Default Sink" | awk '{print $3}')

for i in "${!sinks[@]}"; do
    if [[ "${sinks[$i]}" == "$current" ]]; then
        next_index=$(( (i+1) % ${#sinks[@]} ))
        break
    fi
done

next_sink="${sinks[$next_index]}"
pactl set-default-sink "$next_sink"

for stream in $(pactl list short sink-inputs | awk '{print $1}'); do
    pactl move-sink-input "$stream" "$next_sink"
done

notify-send "Audio Output" "$next_sink"
