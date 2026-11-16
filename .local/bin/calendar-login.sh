#!/usr/bin/env bash
set -euo pipefail

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/vdirsyncer"
DAVMAIL_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/davmail"
HOTMAIL_ACCOUNT="mvrozanti@hotmail.com"
DOWNLOADS="${XDG_DOWNLOAD_DIR:-$HOME/Downloads}"

usage() {
  echo "usage: calendar-login google|hotmail" >&2
  exit 2
}

google_key_steps() {
  cat >&2 <<'EOF'
calendar-login: no Google key yet. Once, in a browser signed in to the Google account:

  1. https://console.cloud.google.com/projectcreate           create a project (any name)
  2. https://console.cloud.google.com/apis/library/caldav.googleapis.com   Enable
  3. https://console.cloud.google.com/auth/overview           Get started: External, your own address
  4. https://console.cloud.google.com/auth/audience           Publish app (otherwise the sign-in dies every 7 days)
  5. https://console.cloud.google.com/auth/clients            Create client: Desktop app, then Download JSON

Leave the downloaded client_secret_*.json in ~/Downloads and run this again.
EOF
  exit 1
}

install_google_key() {
  local newest=""
  local candidate
  shopt -s nullglob
  for candidate in "$DOWNLOADS"/client_secret_*.json; do
    if [ -z "$newest" ] || [ "$candidate" -nt "$newest" ]; then
      newest="$candidate"
    fi
  done
  shopt -u nullglob
  [ -n "$newest" ] || google_key_steps

  if ! jq -e '.installed.client_id and .installed.client_secret' "$newest" >/dev/null; then
    echo "calendar-login: $newest is not a Desktop app key (no .installed block)" >&2
    exit 1
  fi

  umask 077
  jq -r '.installed.client_id' "$newest" > "$STATE/google-client-id"
  jq -r '.installed.client_secret' "$newest" > "$STATE/google-client-secret"
  rm -f "$newest"
  echo "calendar-login: key stored under $STATE, download removed"
}

login_google() {
  if [ ! -s "$STATE/google-client-id" ] || [ ! -s "$STATE/google-client-secret" ]; then
    install_google_key
  fi
  echo "calendar-login: a browser tab opens for the Google sign-in"
  vdirsyncer discover google < <(yes)
  vdirsyncer metasync google
  calendar-sync
  echo "calendar-login: google is syncing every 5 minutes from now on"
}

wait_for_bridge() {
  local attempt
  for attempt in $(seq 1 30); do
    if (exec 3<>"/dev/tcp/127.0.0.1/1080") 2>/dev/null; then
      return 0
    fi
    sleep 1
  done
  echo "calendar-login: davmail did not come up after $attempt tries" >&2
  exit 1
}

login_hotmail() {
  mkdir -p "$DAVMAIL_STATE"
  chmod 700 "$DAVMAIL_STATE"
  calendar-oauth "$HOTMAIL_ACCOUNT" "$DAVMAIL_STATE/tokens.properties"
  systemctl --user restart davmail.service
  wait_for_bridge
  vdirsyncer discover hotmail < <(yes)
  vdirsyncer metasync hotmail
  calendar-sync
  echo "calendar-login: hotmail is syncing every 5 minutes from now on"
}

[ "$#" -eq 1 ] || usage
mkdir -p "$STATE"
chmod 700 "$STATE"

case "$1" in
  google) login_google ;;
  hotmail) login_hotmail ;;
  *) usage ;;
esac
