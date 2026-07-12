for entry in /boot/loader/entries/nixos-generation-*.conf; do
  [ -e "$entry" ] || continue
  gen=$(@coreutils@/bin/basename "$entry" | @gnused@/bin/sed -E 's/^nixos-generation-([0-9]+).*\.conf$/\1/')
  link="/nix/var/nix/profiles/system-${gen}-link"
  if [ -L "$link" ]; then
    ts=$(@coreutils@/bin/stat -c %Y "$link")
    date=$(@coreutils@/bin/date -d "@${ts}" '+%Y-%m-%d %H:%M')
    rev=""
    if [ -r "$link/git-revision" ]; then
      rev=$(@coreutils@/bin/head -c 7 "$link/git-revision")
    fi
    if [ -n "$rev" ]; then
      version="Generation ${gen}, ${rev}, ${date}"
    else
      version="Generation ${gen}, ${date}"
    fi
    @gnused@/bin/sed -i "s|^version .*|version ${version}|" "$entry"
  fi
done
