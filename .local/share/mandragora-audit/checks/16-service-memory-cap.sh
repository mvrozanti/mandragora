#!/usr/bin/env bash
set -uo pipefail
. "$AUDIT_HOME/lib/common.sh"

CHECK="${AUDIT_NAME:-service-memory-cap}"
ALLOWLIST=$(audit_load_allowlist "$MANDRAGORA_REPO/.local/share/mandragora-audit/allowlists/service-memory-cap.txt")

unit_prop() {
  local scope="$1" unit="$2" prop="$3"
  if [ -n "$scope" ]; then
    systemctl "$scope" show "$unit" -p "$prop" --value 2>/dev/null
  else
    systemctl show "$unit" -p "$prop" --value 2>/dev/null
  fi
}

capped() {
  local scope="$1" unit="$2" max slice
  max=$(unit_prop "$scope" "$unit" MemoryMax)
  [ -n "$max" ] || return 1
  [ "$max" != infinity ] && return 0
  slice=$(unit_prop "$scope" "$unit" Slice)
  [ -n "$slice" ] || return 1
  [ "$(unit_prop "$scope" "$slice" MemoryMax)" != infinity ]
}

gpu_units() {
  local scope="$1" f
  shift
  for f in "$@"; do
    [ -e "$f" ] || continue
    grep -qsE '^ConditionPathExists=.*/dev/nvidia0' "$f" || continue
    printf '%s %s\n' "$scope" "$(basename "$f")"
  done
}

user_manager_up() {
  systemctl --user show -p Id --value default.target >/dev/null 2>&1
}

failures=0
checked=0
while read -r scope unit; do
  [ -n "$unit" ] || continue
  audit_in_allowlist "$unit" "$ALLOWLIST" && continue
  checked=$((checked + 1))
  if ! capped "$scope" "$unit"; then
    printf '    %s loads a model on the GPU with no MemoryMax on the unit or its slice: a spill into system RAM is unbounded\n' "$unit" >&2
    failures=$((failures + 1))
  fi
done < <(
  gpu_units "" /etc/systemd/system/*.service
  if user_manager_up; then
    gpu_units "--user" /etc/systemd/user/*.service "$HOME"/.config/systemd/user/*.service
  fi
)

if [ "$failures" -gt 0 ]; then
  audit_fail "$CHECK" "$failures GPU service(s) uncapped; set MemoryMax (vault: incidents/im-gen RAM cap and oom tripwire)"
  exit 1
fi

if user_manager_up; then
  audit_pass "$CHECK" "$checked GPU services capped"
else
  audit_pass "$CHECK" "$checked system GPU services capped; user manager unreachable, user units skipped"
fi
