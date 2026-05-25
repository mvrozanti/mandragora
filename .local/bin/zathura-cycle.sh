#!/usr/bin/env bash
set -euo pipefail

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
    if [[ "$comm" == "zathura" ]]; then
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
  if [[ -n "$ZPID" ]]; then
    file=$(dbus-send --session --print-reply --dest="org.pwmt.zathura.PID-$ZPID" /org/pwmt/zathura org.freedesktop.DBus.Properties.Get string:org.pwmt.zathura string:filename 2>/dev/null | grep -oP 'string "\K[^"]+' || true)
  fi
fi

[[ -z "$file" ]] && exit 1
[[ -z "${ZPID:-}" ]] && exit 1

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

dbus-send --session \
  --dest="org.pwmt.zathura.PID-$ZPID" \
  --type=method_call \
  /org/pwmt/zathura \
  org.pwmt.zathura.OpenDocument \
  string:"$d/$new" string:"" int32:-1
