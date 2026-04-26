#!/usr/bin/env bash
set -euo pipefail

SECRETS_FILE=/etc/nixos/mandragora/secrets/secrets.yaml
AGE_KEY=/persistent/secrets/keys.txt
OBS_LOG_DIR="${HOME}/.config/obs-studio/logs"

obs_running() {
  local pid
  for pid in $(pgrep -x obs 2>/dev/null) $(pgrep -x .obs-wrapped 2>/dev/null); do
    [[ -n "$pid" ]] && return 0
  done
  for pid in /proc/[0-9]*; do
    [[ "$(readlink "$pid/exe" 2>/dev/null)" == */bin/obs ]] && return 0
  done
  return 1
}

obs_recording_status() {
  obs_running || return 1
  [[ -d "$OBS_LOG_DIR" ]] || return 1

  local log
  log=$(find "$OBS_LOG_DIR" -maxdepth 1 -type f -name '*.txt' -printf '%T@\t%p\n' 2>/dev/null \
        | sort -rn | head -1 | cut -f2-)
  [[ -n "$log" && -f "$log" ]] || return 1

  local last
  last=$(grep -E '==== Recording (Start|Stop)' "$log" | tail -1)
  [[ "$last" == *"Recording Start"* ]] || return 1

  local file_line
  file_line=$(grep -E "Writing .* file '" "$log" | tail -1)
  if [[ "$file_line" =~ \'([^\']+)\' ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo "unknown output file"
  fi
  return 0
}

if hit=$(obs_recording_status); then
  echo "sss: OBS is recording (${hit}) — refusing to open ${SECRETS_FILE} in nvim." >&2
  echo "     Stop the recording in OBS first, then re-run sss." >&2
  exit 1
fi

exec sudo SOPS_AGE_KEY_FILE="$AGE_KEY" sops "$SECRETS_FILE" "$@"
