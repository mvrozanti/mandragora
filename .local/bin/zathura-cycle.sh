#!/usr/bin/env bash
set -euo pipefail

LOG=/home/m/zathura_cycle.log
echo "--- $(date) ---" >> $LOG
echo "Args: $*" >> $LOG

notify-send -t 1000 "Zathura" "Cycling document..." || true

dir="next"
case "${1:-}" in
  next|prev) dir="$1"; shift ;;
esac

file="${1:-}"

find_zathura_pid() {
  local apid
  apid=$(hyprctl activewindow -j | jq -r .pid 2>/dev/null || true)
  if [[ -n "$apid" ]] && ps -p "$apid" -o comm= | grep -qE "^zathura$|^\.zathura-wrappe$"; then
    echo "$apid"
    return 0
  fi

  local cp=$PPID
  while [[ $cp -gt 1 ]]; do
    local comm
    comm=$(ps -p "$cp" -o comm= 2>/dev/null || true)
    if [[ "$comm" == "zathura" || "$comm" == ".zathura-wrappe" ]]; then
      echo "$cp"
      return 0
    fi
    cp=$(ps -o ppid= -p "$cp" 2>/dev/null | tr -d ' ' || echo 0)
  done

  pgrep zathura | head -n 1
}

ZPID=$(find_zathura_pid || true)
echo "Resolved ZPID: $ZPID" >> $LOG

if [[ -z "$ZPID" ]]; then
    echo "ERROR: No ZPID" >> $LOG
    exit 1
fi

if [[ -z "$file" ]]; then
    file=$(busctl --user get-property "org.pwmt.zathura.PID-$ZPID" /org/pwmt/zathura org.pwmt.zathura filename 2>/dev/null | grep -oP '"\K[^"]+' || true)
    echo "Found file via busctl: $file" >> $LOG
fi

if [[ -z "$file" ]]; then
    echo "ERROR: No file found" >> $LOG
    exit 1
fi

d=$(dirname "$file")
cur=$(basename "$file")

mapfile -t files < <(
  find "$d" -maxdepth 1 -type f \
    \( -iname '*.pdf' -o -iname '*.epub' -o -iname '*.djvu' \
       -o -iname '*.cbz' -o -iname '*.cbr' -o -iname '*.ps' \
       -o -iname '*.xps' -o -iname '*.fb2' \) \
    -printf '%f\n' | LC_ALL=C sort
)

n=${#files[@]}
(( n > 1 )) || exit 0

idx=-1
for i in "${!files[@]}"; do
  [[ "${files[$i]}" == "$cur" ]] && { idx=$i; break; }
done
(( idx < 0 )) && exit 1

if [[ "$dir" == next ]]; then
  new="${files[$(( (idx + 1) % n ))]}"
else
  new="${files[$(( (idx - 1 + n) % n ))]}"
fi

busctl --user call "org.pwmt.zathura.PID-$ZPID" /org/pwmt/zathura org.pwmt.zathura OpenDocument ssi -- "$d/$new" "" -1
echo "Sent OpenDocument via busctl" >> $LOG
