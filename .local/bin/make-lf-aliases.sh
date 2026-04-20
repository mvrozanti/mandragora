cat ~/.config/lf/lfrc | grep "^map g" | grep -v '\?' | grep cd | awk '{printf "alias z"substr($2, 2)"='\''"; $1=$2=""; print substr($0, 1)"'\''"}' | sed -E 's/\s{2}//g' > ~/.lf_aliases;
