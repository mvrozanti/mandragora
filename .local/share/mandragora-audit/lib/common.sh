audit_red()    { printf '\033[31m%s\033[0m' "$*"; }
audit_yellow() { printf '\033[33m%s\033[0m' "$*"; }
audit_green()  { printf '\033[32m%s\033[0m' "$*"; }
audit_dim()    { printf '\033[2m%s\033[0m' "$*"; }

audit_fail() {
  local check="$1"; shift
  printf '%s %s: %s\n' "$(audit_red FAIL)" "$check" "$*"
}

audit_pass() {
  local check="$1"; shift
  [ -n "${AUDIT_QUIET:-}" ] || printf '%s %s%s\n' "$(audit_green OK  )" "$check" "${1:+: $*}"
}

audit_load_allowlist() {
  local file="$1"
  [ -f "$file" ] || return 0
  grep -vE '^\s*(#|$)' "$file"
}

audit_in_allowlist() {
  local needle="$1" allowlist="$2"
  [ -n "$allowlist" ] || return 1
  printf '%s\n' "$allowlist" | grep -Fxq "$needle"
}

audit_changed_files() {
  if [ -n "${AUDIT_STAGED_FILES:-}" ]; then
    printf '%s\n' "$AUDIT_STAGED_FILES"
  else
    git ls-files
  fi
}
