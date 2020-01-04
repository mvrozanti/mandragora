#!/bin/bash
PDIR="$HOME/.config/polybar"
LAUNCH="polybar-msg cmd restart"
colors=($(head -n16 ~/.cache/wal/colors))
sed -i -e 's/bg = .*/bg = '${colors[ 1]}00'/g' $PDIR/colors.ini
sed -i -e 's/fg = .*/fg = '${colors[ 3]}00'/g' $PDIR/colors.ini
sed -i -e 's/ac = .*/ac = '${colors[ 5]}00'/g' $PDIR/colors.ini
sed -i -e 's/bi = .*/bi = '${colors[ 7]}00'/g' $PDIR/colors.ini
sed -i -e 's/be = .*/be = '${colors[ 9]}00'/g' $PDIR/colors.ini
sed -i -e 's/mf = .*/mf = '${colors[11]}00'/g' $PDIR/colors.ini
$LAUNCH &
