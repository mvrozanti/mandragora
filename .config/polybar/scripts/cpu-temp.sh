sensors | awk '/^Package id 0:/ {
    gsub("\\+","",$4); gsub("°C","",$4);
    temp=$4+0;
    if (temp < 50) {icon=""; color="#00FF00"}
    else if (temp < 60) {icon=""; color="#ADFF2F"}
    else if (temp < 70) {icon=""; color="#FFFF00"}
    else if (temp < 80) {icon=""; color="#FFA500"}
    else {icon=""; color="#FF0000"}
    print "%{T5}%{u" color "}%{+u}" icon " " temp "°C%{-u}%{T-}"
}'

