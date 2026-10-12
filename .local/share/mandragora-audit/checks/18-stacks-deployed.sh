# shellcheck shell=bash
set -uo pipefail
. "$AUDIT_HOME/lib/common.sh"

CHECK="${AUDIT_NAME:-stacks-deployed}"
COMPOSE_REL="nix/hosts/mandragora-vps/compose"
COMPOSE_DIR="$MANDRAGORA_REPO/$COMPOSE_REL"
VPS="${MANDRAGORA_VPS_SSH:-opc@100.84.78.83}"
DRIVER="nix/hosts/mandragora-vps/deploy-stacks.sh"

if [ ! -d "$COMPOSE_DIR" ]; then
  audit_pass "$CHECK" "no compose dir; skipped"
  exit 0
fi
master=$(git -C "$MANDRAGORA_REPO" rev-parse --verify -q refs/heads/master) || {
  audit_pass "$CHECK" "no master ref; skipped"
  exit 0
}

stamps=$(timeout 25 ssh -o BatchMode=yes -o ConnectTimeout=8 "$VPS" \
  'for f in /home/opc/.deployed/*; do [ -f "$f" ] && printf "%s %s\n" "$(basename "$f")" "$(sed -n "s/^commit=//p" "$f")"; done; echo end' 2>/dev/null)
if ! printf '%s\n' "$stamps" | grep -qx end; then
  audit_yellow "    VPS unreachable ($VPS); deployed stacks not compared with master" >&2
  echo >&2
  audit_pass "$CHECK" "skipped (VPS unreachable)"
  exit 0
fi

violations=0
behind=()
stamped=()
while read -r stack stamp; do
  [ -n "$stack" ] && [ "$stack" != end ] || continue
  [ -d "$COMPOSE_DIR/$stack" ] || continue
  stamped+=("$stack")
  if ! git -C "$MANDRAGORA_REPO" cat-file -e "$stamp^{commit}" 2>/dev/null \
    || ! git -C "$MANDRAGORA_REPO" merge-base --is-ancestor "$stamp" "$master"; then
    audit_fail "$CHECK" "live $stack was deployed from ${stamp:0:8}, which master does not contain: unlanded work is being served"
    violations=$((violations + 1))
  elif ! git -C "$MANDRAGORA_REPO" diff --quiet "$stamp" "$master" -- "$COMPOSE_REL/$stack"; then
    behind+=("$stack")
  fi
done <<< "$stamps"

page_files() {
  find . -type f ! -path './vault/*' ! -path './vault-graph/*' ! -name graph.json ! -name .gitkeep \
    -exec md5sum {} + | sort -k2
}

demo_stamp=$(printf '%s\n' "$stamps" | sed -n 's/^demo //p')
if [ -n "$demo_stamp" ] && ! printf '%s\n' "${behind[@]}" | grep -qx demo \
  && git -C "$MANDRAGORA_REPO" merge-base --is-ancestor "$demo_stamp" "$master" 2>/dev/null; then
  tmp=$(mktemp -d)
  git -C "$MANDRAGORA_REPO" archive "$master" "$COMPOSE_REL/demo/static" | tar -x -C "$tmp"
  repo=$(cd "$tmp/$COMPOSE_REL/demo/static" && page_files)
  rm -rf "$tmp"
  live=$(timeout 20 ssh -o BatchMode=yes -o ConnectTimeout=8 "$VPS" \
    "cd /home/opc/demo/static && $(declare -f page_files) && page_files" 2>/dev/null)
  drift=$(diff <(printf '%s\n' "$repo") <(printf '%s\n' "$live") | grep -E '^[<>]' | awk '{print $1, $3}' | sort -u -k2)
  if [ -n "$live" ] && [ -n "$drift" ]; then
    audit_fail "$CHECK" "demo.mvr.ac page files differ from master although its stamp says current (< master, > live):"
    printf '%s\n' "$drift" | sed 's/^/    /' >&2
    violations=$((violations + 1))
  fi
fi

unenrolled=()
for d in "$COMPOSE_DIR"/*/; do
  s=$(basename "$d")
  [ -f "$d/.no-deploy" ] || [ -f "$d/RETIRED.md" ] && continue
  [ -f "$d/docker-compose.yml" ] || [ -f "$d/deploy.sh" ] || continue
  printf '%s\n' "${stamped[@]}" | grep -qx "$s" || unenrolled+=("$s")
done

if [ "${#behind[@]}" -gt 0 ]; then
  audit_yellow "    behind master, the next mandragora-switch deploys them: ${behind[*]}" >&2
  echo >&2
fi
if [ "${#unenrolled[@]}" -gt 0 ]; then
  audit_yellow "    not enrolled (never auto-deployed until live is verified equal to master): ${unenrolled[*]}" >&2
  echo >&2
fi

if [ "$violations" -eq 0 ]; then
  audit_pass "$CHECK" "every enrolled stack is serving a commit master contains"
  exit 0
fi

echo "    Served content is written only by $DRIVER, from master, after a commit lands." >&2
echo "    Land the work being served, or put master back from the main checkout:" >&2
echo "      bash $DRIVER --force <stack>" >&2
exit 1
