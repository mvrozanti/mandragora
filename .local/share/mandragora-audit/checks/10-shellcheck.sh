set -uo pipefail
. "$AUDIT_HOME/lib/common.sh"

CHECK="${AUDIT_NAME:-shellcheck}"
ALLOWLIST=$(audit_load_allowlist "$AUDIT_HOME/allowlists/shellcheck.txt")

is_shell_shebang() {
  local f="$1" first
  [ -f "$f" ] || return 1
  IFS= read -r first < "$f" || return 1
  [[ "$first" =~ ^#!.*(bash|[/[:space:]]sh)([[:space:]]|$) ]]
}

in_scope() {
  case "$1" in
    .local/bin/*|.local/share/*|nix/snippets/*|docs/install/*|agent-skills/*) return 0 ;;
    *) return 1 ;;
  esac
}

mapfile -t CANDIDATES < <(audit_changed_files)

FILES=()
for f in "${CANDIDATES[@]}"; do
  [ -n "$f" ] || continue
  in_scope "$f" || continue
  [ -f "$f" ] || continue
  base=${f##*/}
  case "$base" in
    *.sh) FILES+=("$f") ;;
    *.*) ;;
    *) is_shell_shebang "$f" && FILES+=("$f") ;;
  esac
done

[ "${#FILES[@]}" -eq 0 ] && { audit_pass "$CHECK" "no shell scripts in scope"; exit 0; }

if ! command -v shellcheck >/dev/null 2>&1; then
  audit_pass "$CHECK" "shellcheck unavailable; skipped"
  exit 0
fi

TARGETS=()
for f in "${FILES[@]}"; do
  audit_in_allowlist "$f" "$ALLOWLIST" || TARGETS+=("$f")
done

REPORTS=$(mktemp -d)
trap 'rm -rf "$REPORTS"' EXIT
for i in "${!TARGETS[@]}"; do printf '%s\0%s\0' "$i" "${TARGETS[$i]}"; done \
  | xargs -0 -r -n2 -P"$(nproc)" bash -c 'shellcheck -S warning "$2" >"$0/$1" 2>/dev/null; exit 0' "$REPORTS"

violations=0
for i in "${!TARGETS[@]}"; do
  out=$(cat "$REPORTS/$i" 2>/dev/null)
  [ -z "$out" ] && continue
  audit_fail "$CHECK" "${TARGETS[$i]}"
  printf '%s\n' "$out" | sed 's/^/    /' >&2
  violations=$((violations + 1))
done

if [ "$violations" -eq 0 ]; then
  audit_pass "$CHECK" "shell scripts clean (severity warning+)"
  exit 0
fi
echo "    shellcheck warnings above (severity warning+). Fix the offending lines," >&2
echo "    or grandfather a pre-existing file in allowlists/shellcheck.txt." >&2
exit 1
