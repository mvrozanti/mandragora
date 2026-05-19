cfg=/etc/nixos/mandragora/.git/config
if [ -f "$cfg" ]; then
  target="@auditTree@/hooks"
  current=$(@sed@ -n 's/^[[:space:]]*hooksPath[[:space:]]*=[[:space:]]*//p' "$cfg" | head -n1)
  if [ "$current" != "$target" ]; then
    @sed@ -i '/^\[core\]/,/^\[/ { /hooksPath[[:space:]]*=/d }' "$cfg"
    if @grep@ -q '^\[core\]' "$cfg"; then
      @sed@ -i "/^\[core\]/a\\	hooksPath = $target" "$cfg"
    else
      printf '\n[core]\n\thooksPath = %s\n' "$target" >> "$cfg"
    fi
  fi
fi
