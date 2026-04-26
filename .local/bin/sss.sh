#!/usr/bin/env bash
set -euo pipefail

SECRETS_FILE=/etc/nixos/mandragora/secrets/secrets.yaml
AGE_KEY=/persistent/secrets/keys.txt

obs_recording_pid() {
  local pids pid fd target
  pids=$(pgrep -x obs 2>/dev/null || true)
  [[ -z "$pids" ]] && return 1
  for pid in $pids; do
    [[ -d /proc/$pid/fd ]] || continue
    for fd in /proc/$pid/fd/*; do
      [[ -L "$fd" ]] || continue
      target=$(readlink "$fd" 2>/dev/null || true)
      case "${target,,}" in
        *.mkv|*.mp4|*.flv|*.mov|*.ts|*.m4a|*.webm|*.fragmented_mp4)
          [[ "$target" == /* && "$target" != /dev/* && "$target" != /proc/* ]] || continue
          echo "$pid $target"
          return 0
          ;;
      esac
    done
  done
  return 1
}

if hit=$(obs_recording_pid); then
  echo "sss: OBS appears to be recording (${hit}) — refusing to open ${SECRETS_FILE}." >&2
  echo "     Stop the recording first, then re-run sss." >&2
  exit 1
fi

exec sudo SOPS_AGE_KEY_FILE="$AGE_KEY" sops "$SECRETS_FILE" "$@"
