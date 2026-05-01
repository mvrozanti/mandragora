#!/usr/bin/env bash
set -uo pipefail

AUDIT_HOME="${AUDIT_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
MANDRAGORA_REPO="${MANDRAGORA_REPO:-/etc/nixos/mandragora}"

# shellcheck source=lib/common.sh
. "$AUDIT_HOME/lib/common.sh"

usage() {
  cat <<EOF
Usage: mandragora-audit [--check NAME] [--list] [--quiet]

Repo-invariant test suite. Errors only — exit 0 = clean, 1 = at least one failure.

  --check NAME     Run a single check (basename without .sh, with or without numeric prefix).
  --skip NAME      Skip a check (repeatable). Names match --check semantics.
  --list           List discovered checks and exit.
  --quiet          Suppress per-check OK lines (failures and summary still print).
  --staged         Restrict scope to files in \`git diff --cached --name-only\`.
                   (Used by the pre-commit hook.)

Environment:
  MANDRAGORA_REPO  Repo to audit (default: /etc/nixos/mandragora).
  AUDIT_HOME       Tool root (auto-detected from script location).
EOF
}

ONLY=""
SKIPS=()
LIST=0
STAGED=0
while [ $# -gt 0 ]; do
  case "$1" in
    --check) ONLY="$2"; shift 2 ;;
    --skip)  SKIPS+=("$2"); shift 2 ;;
    --list)  LIST=1; shift ;;
    --quiet) export AUDIT_QUIET=1; shift ;;
    --staged) STAGED=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

check_matches() {
  local name="$1" target="$2"
  local stripped=${name#[0-9][0-9]-}
  [ "$name" = "$target" ] || [ "$stripped" = "$target" ]
}

[ -d "$MANDRAGORA_REPO" ] || { echo "MANDRAGORA_REPO not found: $MANDRAGORA_REPO" >&2; exit 2; }
cd "$MANDRAGORA_REPO"

if [ "$STAGED" -eq 1 ]; then
  AUDIT_STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null || true)
  export AUDIT_STAGED_FILES
fi

shopt -s nullglob
CHECKS=("$AUDIT_HOME"/checks/*.sh)
shopt -u nullglob

if [ "$LIST" -eq 1 ]; then
  for c in "${CHECKS[@]}"; do printf '%s\n' "$(basename "$c" .sh)"; done
  exit 0
fi

if [ -n "$ONLY" ]; then
  filtered=()
  for c in "${CHECKS[@]}"; do
    name=$(basename "$c" .sh)
    if check_matches "$name" "$ONLY"; then filtered+=("$c"); fi
  done
  if [ "${#filtered[@]}" -eq 0 ]; then
    echo "no check matched: $ONLY" >&2
    exit 2
  fi
  CHECKS=("${filtered[@]}")
fi

if [ "${#SKIPS[@]}" -gt 0 ]; then
  filtered=()
  for c in "${CHECKS[@]}"; do
    name=$(basename "$c" .sh)
    skip=0
    for s in "${SKIPS[@]}"; do
      if check_matches "$name" "$s"; then skip=1; break; fi
    done
    [ "$skip" -eq 0 ] && filtered+=("$c")
  done
  CHECKS=("${filtered[@]}")
fi

FAILED=0
RAN=0
for check in "${CHECKS[@]}"; do
  RAN=$((RAN + 1))
  name=$(basename "$check" .sh)
  if ! AUDIT_NAME="$name" bash "$check"; then
    FAILED=$((FAILED + 1))
  fi
done

echo
if [ "$FAILED" -eq 0 ]; then
  printf '%s %d/%d checks passed\n' "$(audit_green PASS)" "$RAN" "$RAN"
  exit 0
else
  printf '%s %d/%d checks failed\n' "$(audit_red FAIL)" "$FAILED" "$RAN"
  exit 1
fi
