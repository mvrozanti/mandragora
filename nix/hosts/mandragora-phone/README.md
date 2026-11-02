# `mandragora-phone` — the phone as a host

An Android phone on the tailnet, treated the way the kindle is: not NixOS,
declared in the repo, reproducible from a short recipe, and served by the
desktop over the tailnet. Overview and intent: [`docs/phone.md`](../../../docs/phone.md).
Ideas and constraints: [`BACKLOG.md`](BACKLOG.md).

```
tailnet ip          nix/snippets/tailnet.json  →  phone
syncthing identity  identity.json              →  deviceId, port
desktop services    phone-bridge :6688, mpd :6600, ytdl-web :6685, gpu-status :6684
the app             app/  (built in `nix develop /etc/nixos/mandragora#phone`, shipped by `phone-push`)
```

## What the phone runs

| app | role | source of truth |
|---|---|---|
| Tailscale | the only network path the desktop trusts | tailnet admin; ip in `tailnet.json` |
| Sync-Fork (`com.github.catfriend1.syncthingandroid`) | Music receive-only, six inbox folders send-receive | `identity.json`, `nix/modules/desktop/syncthing.nix`, `phone-syncthing-bootstrap` |
| KDE Connect | clipboard, notifications, trackpad, system volume fallback | `nix/modules/desktop/kdeconnect.nix` |
| DroidCam | mjpeg for the kindle camera widget | `nix/modules/services/kindle-cam.nix` |
| mandragora (this repo's app) | remote, player, lyrics, ytdl client, hub portal | `app/` |

## What the desktop serves for it

All of it on the tailnet interface only; nothing here has a `*.mvr.ac` host.

| port | unit | what |
|---|---|---|
| 6688 | `phone-bridge` (user) | `GET /api/config` (desktop ip, ports, hub manifest); `GET/POST /api/volume` (default sink, all sinks, set level, mute, default); `GET/POST /api/lease`, `POST /api/lease/position` (who plays, where, since); `GET /api/lyrics?file=` (`.lrc` beside the track, then the `~/Music/.lyrics` cache, then lrclib, writing the `.lrc` when synced lyrics exist); `GET /api/now` |
| 6600 | mpd (user) | the mpd protocol; the app uses `idle` for push updates. No password: every tailnet node is the operator's |
| 6685 | `ytdl-web` (user) | `POST /api/download`, `GET /api/jobs`, `/api/jobs/<id>/file`, `/cancel` |
| 6684 | `gpu-status` | `GET /api/theme?colors=1`, the matugen palette the app wears |

Source for the bridge: [`bridge/server.py`](bridge/server.py), module
`nix/modules/services/phone-bridge.nix`. State: `~/.local/state/phone-bridge/lease.json`.

### The lease

Exactly one device plays. `lease.owner` is `desk` or `phone`.

- `POST /api/lease {"owner":"phone"}`: mpd pauses, the current file and second
  are recorded, the phone plays its synced copy from that second.
- `POST /api/lease/position {...}` every few seconds while the phone plays, and
  on pause: the desktop always knows where the phone is.
- `POST /api/lease {"owner":"desk"}`: mpd plays the recorded file from the
  recorded second (added to the queue if it is not there), paused if the phone
  was paused.
- `GET /api/lease` with the desk owning reads live mpd state; with the phone
  owning returns the last heartbeat.

When the tailnet is down the app shows the last known desk state, freezes the
desk controls, keeps local playback working, and offers "play here from the
last known second". It never falls back to a public host.

## Bootstrap from scratch

1. **Tailscale**: install, sign in, enable *Always-on VPN* and *Block
   connections without VPN* in Android's VPN settings, set the app's battery
   use to *Unrestricted*. Confirm the ip matches `tailnet.json` or update it.
2. **Sync-Fork**: install from F-Droid, set battery to *Unrestricted*, pair
   with the desktop (accept the pending device on the desktop GUI at
   `127.0.0.1:8384`). If the phone's device id changed, update
   `identity.json`. Regenerate the GUI API key (Settings → GUI → API Key) and
   keep it only on the phone; the bootstrap script reads it from the
   environment at run time. Then, with wireless debugging on:
   `PHONE_ADB_ADDR=<ip:port> PHONE_API_KEY=<key> DESKTOP_DEVICE_ID=<id> phone-syncthing-bootstrap`.
   Details and the trashcan-versioning trap: vault note *Syncthing phone drain*.
3. **KDE Connect**: pair; enable system volume and run command on the phone side.
4. **Wireless debugging**: Developer options → Wireless debugging → pair with
   code once from the desktop (`adb pair <ip:pairport>`), then every push uses
   `adb connect <ip:port>`; the port changes per session, read it off the
   screen. `~/Projects/android-music-sync/setup_adb.sh` has the walkthrough.
5. **The app**: `PHONE_ADB_ADDR=<ip:port> phone-push`. First install asks the
   phone to allow the install; later installs are silent. Open it once so the
   share target registers, grant notifications and music access, and paste
   Sync-Fork's API key into the sync sheet.

## Building the app

`app/` is a plain Gradle project (AGP 8.7, Kotlin 2.1, Compose, Media3). The
SDK comes from the `phone` dev shell (`android-nixpkgs`: platform 35,
build-tools 35, platform-tools), so nothing is installed under `~/Android`.

```
cd nix/hosts/mandragora-phone/app
nix develop /etc/nixos/mandragora#phone -c ./gradlew assembleDebug
```

- The SDK lives in the nix store and is read-only, so `buildToolsVersion` is
  pinned to the one the shell provides; AGP's default would try to download
  another and fail.
- The aapt2 Gradle pulls from Maven is a generic Linux binary that cannot run
  on NixOS; the shell points `android.aapt2FromMavenOverride` at the SDK's.
- The desktop's tailnet ip is compiled in from `nix/snippets/tailnet.json`
  (`MANDRAGORA_DESKTOP_IP`); everything else comes from the bridge at runtime.
- Signing: `phone-push` builds **debug** unless `PHONE_KEYSTORE` is set. The
  debug key is `~/.android/debug.keystore`. Moving to a release key later
  changes the signature, which Android only accepts after an uninstall.

Everything after step 1 is reachable only over the tailnet, so step 1 is the
whole security model: no tailnet, no phone.

## Traps

- Android stops background VPNs under battery pressure. Without *Always-on*
  and *Unrestricted*, the app is dead exactly when it is reached for.
- Sync-Fork's default trashcan versioning once held 17 GB on the phone.
  `phone-syncthing-bootstrap` posts folders with `versioning: ""`.
- The Sync-Fork GUI is localhost-only on the phone; the desktop reaches it
  through `adb forward tcp:18384 tcp:8384`, never over the network.
- `music.stignore` re-includes audio extensions and `*.lrc` only. A new file
  type for the phone needs a line there, or it never arrives.
- Wireless debugging's connect port is not the pairing port, and both change.
- The phone hotspot does not forward ICMP; failover scripts cannot ping it.
