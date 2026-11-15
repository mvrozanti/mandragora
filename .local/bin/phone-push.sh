#!/usr/bin/env bash
set -euo pipefail

REPO="${MANDRAGORA_REPO:-/etc/nixos/mandragora}"
APP="$REPO/nix/hosts/mandragora-phone/app"
SLOT="${PHONE_APP_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mandragora-phone/app}"
if [ -n "${PHONE_KEYSTORE:-}" ]; then
  VARIANT="${PHONE_APK_VARIANT:-release}"
else
  VARIANT="${PHONE_APK_VARIANT:-debug}"
fi
APK="${PHONE_APK:-}"

if [ -z "$APK" ]; then
  [ -f "$APP/gradlew" ] || { echo "phone-push: no app at $APP" >&2; exit 1; }
  echo "phone-push: building $VARIANT in $APP"
  (cd "$APP" && nix develop "$REPO#phone" -c ./gradlew --quiet "assemble${VARIANT^}")
  APK=$(find "$APP/app/build/outputs/apk/$VARIANT" -name '*.apk' | sort | head -1)
fi
[ -f "$APK" ] || { echo "phone-push: no apk found" >&2; exit 1; }

if [ -n "${PHONE_ADB_ADDR:-}" ]; then
  adb connect "$PHONE_ADB_ADDR" > /dev/null
  adb -s "$PHONE_ADB_ADDR" install -r "$APK"
  echo "phone-push: installed $(basename "$APK") on $PHONE_ADB_ADDR"
  exit 0
fi

sdk=$(nix develop "$REPO#phone" -c printenv ANDROID_HOME)
aapt2=$(find "$sdk/build-tools" -name aapt2 -print -quit)
[ -x "$aapt2" ] || { echo "phone-push: no aapt2 in the phone dev shell" >&2; exit 1; }
badging=$("$aapt2" dump badging "$APK")
version_code=$(printf '%s\n' "$badging" | sed -n "s/^package: .*versionCode='\([0-9]*\)'.*/\1/p")
version_name=$(printf '%s\n' "$badging" | sed -n "s/^package: .*versionName='\([^']*\)'.*/\1/p")
[ -n "$version_code" ] || { echo "phone-push: could not read the version from $APK" >&2; exit 1; }

mkdir -p "$SLOT"
cp -f "$APK" "$SLOT/mandragora-phone.apk.tmp"
mv -f "$SLOT/mandragora-phone.apk.tmp" "$SLOT/mandragora-phone.apk"
python3 -I - "$SLOT" "$version_code" "$version_name" "$VARIANT" <<'PY'
import hashlib, json, os, sys, time
slot, code, name, variant = sys.argv[1:5]
apk = os.path.join(slot, "mandragora-phone.apk")
digest = hashlib.sha256()
with open(apk, "rb") as fh:
    for chunk in iter(lambda: fh.read(1 << 20), b""):
        digest.update(chunk)
meta = {"versionCode": int(code), "versionName": name, "sha256": digest.hexdigest(), "size": os.path.getsize(apk), "variant": variant, "publishedAt": time.time()}
tmp = os.path.join(slot, "app.json.tmp")
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump(meta, fh)
os.replace(tmp, os.path.join(slot, "app.json"))
PY
echo "phone-push: published $version_name ($version_code, $VARIANT) to $SLOT; the app offers it on its next check"
