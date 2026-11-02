#!/usr/bin/env bash
set -euo pipefail

REPO="${MANDRAGORA_REPO:-/etc/nixos/mandragora}"
APP="$REPO/nix/hosts/mandragora-phone/app"
if [ -n "${PHONE_KEYSTORE:-}" ]; then
  VARIANT="${PHONE_APK_VARIANT:-release}"
else
  VARIANT="${PHONE_APK_VARIANT:-debug}"
fi
APK="${PHONE_APK:-}"

: "${PHONE_ADB_ADDR:?need PHONE_ADB_ADDR (wireless debugging ip:port on the tailnet, e.g. 100.114.176.5:33391)}"

if [ -z "$APK" ]; then
  [ -f "$APP/gradlew" ] || { echo "phone-push: no app at $APP" >&2; exit 1; }
  echo "phone-push: building $VARIANT in $APP"
  (cd "$APP" && nix develop "$REPO#phone" -c ./gradlew --quiet "assemble${VARIANT^}")
  APK=$(find "$APP/app/build/outputs/apk/$VARIANT" -name '*.apk' | sort | head -1)
fi

[ -f "$APK" ] || { echo "phone-push: no apk found" >&2; exit 1; }

adb connect "$PHONE_ADB_ADDR" >/dev/null
adb -s "$PHONE_ADB_ADDR" install -r "$APK"
echo "phone-push: installed $(basename "$APK") on $PHONE_ADB_ADDR"
