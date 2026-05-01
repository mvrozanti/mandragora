set -uo pipefail
. "$AUDIT_HOME/lib/common.sh"

CHECK="${AUDIT_NAME:-doc-links}"

# Verify that every relative [text](path) link in tracked Markdown resolves.
# Skips: URLs (scheme://, mailto:), fragment-only (#sec), home-relative (~/...).
# Strips fragments (path.md#sec) before stat-ing.

mapfile -t MD_FILES < <(audit_changed_files | grep -E '\.md$')

violations=0
for md in "${MD_FILES[@]}"; do
  [ -f "$md" ] || continue
  dir=$(dirname "$md")

  # rg returns: line:col:match. We want line + the URL part of [text](url).
  # Multiline turned off; assume each link fits on one line.
  while IFS= read -r match; do
    line=${match%%:*}
    rest=${match#*:}
    url=${rest#*\(}
    url=${url%%\)*}

    case "$url" in
      ''|'#'*|*://*|mailto:*|'~/'*) continue ;;
    esac

    target=${url%%#*}
    [ -z "$target" ] && continue

    case "$target" in
      /*) resolved="$target" ;;
      *)  resolved="$dir/$target" ;;
    esac

    if [ ! -e "$resolved" ]; then
      audit_fail "$CHECK" "$md:$line broken link -> $url"
      violations=$((violations + 1))
    fi
  done < <(grep -nEo '\[[^]]+\]\([^)]+\)' "$md" 2>/dev/null || true)
done

if [ "$violations" -eq 0 ]; then
  audit_pass "$CHECK" "all relative doc links resolve"
  exit 0
fi
exit 1
