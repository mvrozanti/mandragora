sensors | awk '/^Package id 0:/ {
    gsub("\\+","",$4); gsub("°C","",$4);
    temp=$4+0;
    if (temp < 40) icon="";
    else if (temp < 55) icon="";
    else if (temp < 65) icon="";
    else if (temp < 75) icon="";
    else icon="";
    print "%{T5}" icon " " temp "°C%{T-}"
}'
