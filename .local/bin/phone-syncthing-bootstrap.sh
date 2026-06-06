#!/usr/bin/env bash
set -euo pipefail

# Bootstraps the Android phone's Sync-Fork folder layout against the desktop.
# Re-run idempotently after a phone factory reset or Sync-Fork reinstall.
#
# Pre-reqs:
#   1. Phone running Sync-Fork (Catfriend1 fork from F-Droid).
#   2. Phone paired to desktop (device ID added in desktop's syncthing.nix).
#   3. Wireless debugging on phone reachable from this host.
#   4. Sync-Fork's web GUI API key known.
#
# Env vars:
#   PHONE_ADB_ADDR     e.g. 100.114.176.5:33391 (the adb connect target)
#   PHONE_API_KEY      from Sync-Fork web GUI, Settings, GUI, API Key
#   DESKTOP_DEVICE_ID  syncthing device ID of this host (syncthing --device-id or rest/system/status)
#
# Example:
#   PHONE_ADB_ADDR=100.114.176.5:33391 \
#   PHONE_API_KEY=6f3titADVL7hpA5M476oTcU7CiSoxdFF \
#   DESKTOP_DEVICE_ID=7TQ4W3A-C4EN6V5-DYMCUTE-JP6Z3GJ-IM2YISO-REFU7WA-MWUVHBI-KCFDXAF \
#   phone-syncthing-bootstrap.sh

: "${PHONE_ADB_ADDR:?need PHONE_ADB_ADDR (e.g. 100.114.176.5:33391)}"
: "${PHONE_API_KEY:?need PHONE_API_KEY from Sync-Fork web GUI}"
: "${DESKTOP_DEVICE_ID:?need DESKTOP_DEVICE_ID (this hosts syncthing device ID)}"

LOCAL_FORWARD_PORT="${LOCAL_FORWARD_PORT:-18384}"
PHONE_API_BASE="https://127.0.0.1:${LOCAL_FORWARD_PORT}"

adb connect "$PHONE_ADB_ADDR" >/dev/null
adb -s "$PHONE_ADB_ADDR" forward "tcp:${LOCAL_FORWARD_PORT}" tcp:8384 >/dev/null

post_folder() {
  local id="$1" label="$2" path="$3" ftype="$4"
  local body
  body=$(jq -nc --arg id "$id" --arg label "$label" --arg path "$path" --arg ftype "$ftype" --arg desktop "$DESKTOP_DEVICE_ID" '{id: $id, label: $label, path: $path, type: $ftype, devices: [{deviceID: $desktop}], ignorePerms: true, rescanIntervalS: 60, fsWatcherEnabled: true, versioning: {type: ""}}')
  curl -sk -H "X-API-Key: $PHONE_API_KEY" -H "Content-Type: application/json" \
    -X POST --data "$body" "$PHONE_API_BASE/rest/config/folders" >/dev/null
  echo "posted: $id -> $path ($ftype)"
}

# drain buckets (phone is producer, desktop archives)
post_folder mandragora-phone-dcim       "Phone DCIM"        /storage/emulated/0/DCIM                                          sendreceive
post_folder mandragora-phone-pictures   "Phone Pictures"    /storage/emulated/0/Pictures                                      sendreceive
post_folder mandragora-phone-movies     "Phone Movies"      /storage/emulated/0/Movies                                        sendreceive
post_folder mandragora-phone-whatsapp   "Phone WhatsApp"    /storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media     sendreceive
post_folder mandragora-phone-recordings "Phone Recordings"  /storage/emulated/0/Recordings                                    sendreceive
post_folder mandragora-phone-downloads  "Phone Downloads"   /storage/emulated/0/Download                                      sendreceive

# music push (desktop is master, phone is read replica)
post_folder mandragora-music            "Music"             /storage/emulated/0/Music                                         receiveonly

echo
echo "verifying:"
curl -sk -H "X-API-Key: $PHONE_API_KEY" "$PHONE_API_BASE/rest/config/folders" | python3 - <<'PYEOF'
import json, sys
for f in json.load(sys.stdin):
    v = f.get("versioning", {}).get("type", "") or "none"
    print(f"  {f['id']:35s} {f['type']:12s} versioning={v:8s} {f['path']}")
PYEOF

