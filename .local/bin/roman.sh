#!/usr/bin/env bash
num2roman() {
    input=$1
    output=""
    len=${#input}

    roman_val() {
        N=$1 one=$2 five=$3 ten=$4 out=""
        case $N in
            0) out="" ;;
            [123]) while [[ $N -gt 0 ]]; do out+="$one"; N=$((N-1)); done ;;
            4) out+="$one$five" ;;
            5) out+="$five" ;;
            [678]) out+="$five"; N=$((N-5)); while [[ $N -gt 0 ]]; do out+="$one"; N=$((N-1)); done ;;
            9) while [[ $N -lt 10 ]]; do out+="$one"; N=$((N+1)); done; out+="$ten" ;;
        esac
        echo $out
    }

    while [[ $len -gt 0 ]]; do
        num=${input:0:1}
        case $len in
            1) output+="$(roman_val $num I V X)" ;;
            2) output+="$(roman_val $num X L C)" ;;
            3) output+="$(roman_val $num C D M)" ;;
            *) num=${input:0:(-3)}
               while [[ $num -gt 0 ]]; do output+="M"; num=$((num-1)); done ;;
        esac
        input=${input:1}; len=${#input}
    done
    echo $output
}

num2roman "$1"
