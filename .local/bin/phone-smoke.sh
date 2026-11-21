#!/usr/bin/env bash
set -euo pipefail

REPO="${MANDRAGORA_REPO:-/etc/nixos/mandragora}"
export MANDRAGORA_REPO="$REPO"
export PHONE_EMU_NAME="${PHONE_EMU_NAME:-mandragora-phone-check}"
export PHONE_EMU_PORT="${PHONE_EMU_PORT:-5560}"
export PHONE_EMU_HEADLESS=1
SERIAL="emulator-$PHONE_EMU_PORT"
PACKAGE="ac.mvr.phone"
MODE="${1:-check}"

if [ -z "${PHONE_SMOKE_INSIDE:-}" ]; then
  exec env PHONE_SMOKE_INSIDE=1 PHONE_EMU_INSIDE=1 nix develop "$REPO#phone" -c "$0" "$@"
fi
export ANDROID_USER_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/mandragora-phone/android"
export ANDROID_AVD_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/mandragora-phone/avd"
export ANDROID_EMULATOR_HOME="$ANDROID_USER_HOME"

a() { adb -s "$SERIAL" "$@"; }

stop_emulator() {
  a emu kill > /dev/null 2>&1 || true
  for _ in $(seq 30); do
    a get-state > /dev/null 2>&1 || return 0
    sleep 1
  done
}

if [ "$MODE" = boot ]; then
  stop_emulator
  PHONE_EMU_BOOT_ONLY=1 bash "$REPO/.local/bin/phone-emu.sh" > /dev/null
  exit 0
fi

START=$SECONDS
say() { echo "phone-smoke: $* ($((SECONDS - START)) s)"; }

fail() {
  echo "phone-smoke: FAIL: $*" >&2
  stop_emulator
  exit 1
}

crashes() { a logcat -d -b crash 2> /dev/null | grep -A12 "Process: $PACKAGE" || true; }

foreground_services() {
  a shell dumpsys activity services "$PACKAGE" 2> /dev/null | tr -d '\r' |
    awk '/ServiceRecord\{/ { for (i = 1; i <= NF; i++) if ($i ~ /\//) name = $i; sub(/\}$/, "", name); sub(/.*\//, "", name); n = split(name, part, "."); name = part[n-1] "." part[n] }
         /isForeground=true/ { print name }' | sort -u
}

EXPECTED_SERVICES="inbox.InboxService
play.PlaybackService"

running() { [ -n "$(a shell pidof "$PACKAGE" 2> /dev/null | tr -d '\r')" ]; }

within() {
  local seconds="$1"
  shift
  for _ in $(seq "$seconds"); do
    "$@" && return 0
    sleep 1
  done
  return 1
}

booted() {
  a wait-for-device
  until [ "$(a shell getprop sys.boot_completed 2> /dev/null | tr -d '\r')" = "1" ]; do sleep 1; done
}

expected_services() { [ "$(foreground_services)" = "$EXPECTED_SERVICES" ]; }

[ -n "${PHONE_SMOKE_BOOTED:-}" ] || stop_emulator
bash "$REPO/.local/bin/phone-emu.sh" > /dev/null
say "booted, installed, launched"

within 15 running || fail "the app never started$(printf '\n%s' "$(crashes)")"
sleep 3
running || fail "the app died right after starting$(printf '\n%s' "$(crashes)")"

a shell input keyevent KEYCODE_HOME
a shell input keyevent KEYCODE_SLEEP
within 20 expected_services || true
sleep 2
services=$(foreground_services | paste -sd, -)
expected_services || fail "foreground services after locking: ${services:-none}; expected only the music player and the inbox listener"
running || fail "the app died after locking$(printf '\n%s' "$(crashes)")"
[ -z "$(crashes)" ] || fail "crashed while in use:$(printf '\n%s' "$(crashes)")"
say "runs, locks, only the music player and the inbox listener in the foreground, no crash"

a reboot
booted
sleep 10
[ -z "$(crashes)" ] || fail "crashed during or after boot:$(printf '\n%s' "$(crashes)")"
say "survives a reboot"

stop_emulator
say "passed"
