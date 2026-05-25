#!/usr/bin/env bash
set -euo pipefail

LOG=/home/m/zathura_cycle.log
echo "--- $(date) ---" >> $LOG
echo "Args: $*" >> $LOG
echo "PPID: $PPID" >> $LOG

dir="next"
case "${1:-}" in
  next|prev) dir="$1"; shift ;;
esac

file="${1:-}"

find_zathura_pid() {
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
  return 1
}

ZPID=""
if [[ -z "$file" ]]; then
  ZPID=$(find_zathura_pid || true)
  echo "Found ZPID via tree: $ZPID" >> $LOG
  if [[ -n "$ZPID" ]]; then
    file=$(busctl --user get-property "org.pwmt.zathura.PID-$ZPID" /org/pwmt/zathura org.pwmt.zathura filename 2>/dev/null | grep -oP '"\K[^"]+' || true)
    echo "Found file via busctl: $file" >> $LOG
  fi
fi

if [[ -z "$file" ]]; then
    # Fallback to any zathura if we can't find the parent
    ZPID=$(pgrep zathura | head -n 1 || true)
    echo "Fallback ZPID (pgrep): $ZPID" >> $LOG
    if [[ -n "$ZPID" ]]; then
        file=$(busctl --user get-property "org.pwmt.zathura.PID-$ZPID" /org/pwmt/zathura org.pwmt.zathura filename 2>/dev/null | grep -oP '"\K[^"]+' || true)
        echo "Fallback file: $file" >> $LOG
    fi
fi

if [[ -z "$file" ]]; then
    echo "ERROR: No file found" >> $LOG
    exit 1
fi

[[ -z "${ZPID:-}" ]] && { echo "ERROR: No ZPID" >> $LOG; exit 1; }

d=$(dirname "$file")
cur=$(basename "$file")
echo "Dir: $d, Cur: $cur" >> $LOG

mapfile -t files < <(
  find "$d" -maxdepth 1 -type f \
    \( -iname '*.pdf' -o -iname '*.epub' -o -iname '*.djvu' \
       -o -iname '*.cbz' -o -iname '*.cbr' -o -iname '*.ps' \
       -o -iname '*.xps' -o -iname '*.fb2' \) \
    -printf '%f\n' | LC_ALL=C sort
)

n=${#files[@]}
echo "Compatible files: $n" >> $LOG
(( n > 1 )) || exit 0

idx=-1
for i in "${!files[@]}"; do
  [[ "${files[$i]}" == "$cur" ]] && { idx=$i; break; }
done
echo "Current index: $idx" >> $LOG
(( idx < 0 )) && { echo "ERROR: Current file not in list" >> $LOG; exit 1; }

if [[ "$dir" == next ]]; then
  new="${files[$(( (idx + 1) % n ))]}"
else
  new="${files[$(( (idx - 1 + n) % n ))]}"
fi
echo "New file: $new" >> $LOG

busctl --user call "org.pwmt.zathura.PID-$ZPID" /org/pwmt/zathura org.pwmt.zathura OpenDocument ss i "$d/$new" "" -1
echo "Sent OpenDocument via busctl" >> $LOG
