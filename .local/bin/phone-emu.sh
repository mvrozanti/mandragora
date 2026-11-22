#!/usr/bin/env bash
set -euo pipefail

REPO="${MANDRAGORA_REPO:-/etc/nixos/mandragora}"
APP="$REPO/nix/hosts/mandragora-phone/app"
STATE="${XDG_DATA_HOME:-$HOME/.local/share}/mandragora-phone"
NAME="${PHONE_EMU_NAME:-mandragora-phone}"
IMAGE="system-images;android-35;google_apis;x86_64"
PORT="${PHONE_EMU_PORT:-5554}"
SERIAL="emulator-$PORT"
PACKAGE="ac.mvr.phone"

if [ -z "${PHONE_EMU_INSIDE:-}" ]; then
  exec env PHONE_EMU_INSIDE=1 nix develop "$REPO#phone" -c "$0" "$@"
fi

export ANDROID_USER_HOME="$STATE/android"
export ANDROID_AVD_HOME="$STATE/avd"
export ANDROID_EMULATOR_HOME="$STATE/android"
mkdir -p "$ANDROID_AVD_HOME" "$ANDROID_USER_HOME"
[ -f "$HOME/.android/debug.keystore" ] && command cp -f "$HOME/.android/debug.keystore" "$ANDROID_USER_HOME/debug.keystore"

set_ini() {
  local file="$1" key="$2" value="$3"
  sed -i "/^${key}=/d" "$file"
  printf '%s=%s\n' "$key" "$value" >> "$file"
}

if [ ! -d "$ANDROID_AVD_HOME/$NAME.avd" ]; then
  echo "phone-emu: creating the virtual device"
  echo no | avdmanager create avd -n "$NAME" -k "$IMAGE" -d pixel_6a --force > /dev/null
  ini="$ANDROID_AVD_HOME/$NAME.avd/config.ini"
  set_ini "$ini" hw.keyboard yes
  set_ini "$ini" hw.lcd.width 1080
  set_ini "$ini" hw.lcd.height 2400
  set_ini "$ini" hw.lcd.density 400
  set_ini "$ini" hw.ramSize 3072
  set_ini "$ini" disk.dataPartition.size 4G
  set_ini "$ini" hw.audioOutput yes
fi

if ! adb -s "$SERIAL" get-state > /dev/null 2>&1; then
  echo "phone-emu: booting (log: $STATE/emulator-$NAME.log)"
  window=()
  [ -n "${PHONE_EMU_HEADLESS:-}" ] && window=(-no-window -no-audio -no-snapshot)
  setsid -f emulator -avd "$NAME" -port "$PORT" -gpu "${PHONE_EMU_GPU:-swiftshader_indirect}" -no-boot-anim "${window[@]}" > "$STATE/emulator-$NAME.log" 2>&1 < /dev/null
fi
[ -n "${PHONE_EMU_BOOT_ONLY:-}" ] && exit 0

adb -s "$SERIAL" wait-for-device
until [ "$(adb -s "$SERIAL" shell getprop sys.boot_completed 2> /dev/null | tr -d '\r')" = "1" ]; do
  sleep 2
done

APK="${PHONE_APK:-}"
if [ -z "$APK" ]; then
  echo "phone-emu: building the debug apk"
  (cd "$APP" && ./gradlew --quiet assembleDebug)
  APK=$(find "$APP/app/build/outputs/apk/debug" -name '*.apk' | sort | head -1)
fi
[ -f "$APK" ] || { echo "phone-emu: no apk found" >&2; exit 1; }

if ! out=$(adb -s "$SERIAL" install -r "$APK" 2>&1); then
  case "$out" in
    *INSTALL_FAILED_UPDATE_INCOMPATIBLE*)
      echo "phone-emu: replacing an app signed with another key"
      adb -s "$SERIAL" uninstall "$PACKAGE" > /dev/null
      adb -s "$SERIAL" install -r "$APK" > /dev/null ;;
    *) echo "$out" >&2; exit 1 ;;
  esac
fi
adb -s "$SERIAL" shell pm grant "$PACKAGE" android.permission.POST_NOTIFICATIONS 2> /dev/null || true
adb -s "$SERIAL" shell pm grant "$PACKAGE" android.permission.READ_MEDIA_AUDIO 2> /dev/null || true

MUSIC="${PHONE_EMU_MUSIC:-$HOME/Music}"
current=$(mpc -f %file% current 2> /dev/null || true)
count=0
while IFS= read -r file; do
  [ -n "$file" ] && [ -f "$MUSIC/$file" ] || continue
  adb -s "$SERIAL" push --sync "$MUSIC/$file" "/sdcard/Music/$file" > /dev/null < /dev/null
  count=$((count + 1))
done < <(
  printf '%s\n' "$current"
  find "$MUSIC" -maxdepth 1 -type f \( -name '*.mp3' -o -name '*.m4a' -o -name '*.opus' -o -name '*.flac' \) -printf '%T@ %P\n' | sort -rn | head -12 | cut -d' ' -f2-
)

adb -s "$SERIAL" shell input keyevent KEYCODE_WAKEUP
adb -s "$SERIAL" shell wm dismiss-keyguard
adb -s "$SERIAL" shell am start -n "$PACKAGE/.MainActivity" > /dev/null
echo "phone-emu: $(basename "$APK") running on $SERIAL; $count song(s) in its Music folder"
