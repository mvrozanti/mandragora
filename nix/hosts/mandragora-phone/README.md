# `mandragora-phone` — the phone as a host

An Android phone on the tailnet, treated the way the kindle is: not NixOS,
declared in the repo, reproducible from a short recipe, and served by the
desktop over the tailnet. Overview and intent: [`docs/phone.md`](../../../docs/phone.md).
Ideas and constraints: [`BACKLOG.md`](BACKLOG.md).

```
tailnet ip          nix/snippets/tailnet.json  →  phone
syncthing identity  identity.json              →  deviceId, port
desktop services    phone-bridge :6688, mpd :6600, ytdl-web :6685, gpu-status :6684
the app             app/  (built in `nix develop /etc/nixos/mandragora#phone`, published by `phone-push`, installed by the app itself)
```

## What the phone runs

| app | role | source of truth |
|---|---|---|
| Tailscale | the only network path the desktop trusts | tailnet admin; ip in `tailnet.json` |
| Sync-Fork (`com.github.catfriend1.syncthingandroid`) | Music receive-only, six inbox folders send-receive | `identity.json`, `nix/modules/desktop/syncthing.nix`, `phone-syncthing-bootstrap` |
| KDE Connect | clipboard, notifications, trackpad, system volume fallback | `nix/modules/desktop/kdeconnect.nix` |
| DroidCam | mjpeg for the kindle camera widget | `nix/modules/services/kindle-cam.nix` |
| mandragora (this repo's app) | one screen: desktop volume, the pill that moves the music, the song, "play something" | `app/` |

## What the desktop serves for it

All of it on the tailnet interface only; nothing here has a `*.mvr.ac` host.

| port | unit | what |
|---|---|---|
| 4096 | `opencode-serve` (user) | the opencode HTTP server, the one the desktop `oc` tui attaches to: sessions, messages, `prompt_async`, `abort`, the `/event` stream, permission and question replies, `/project`, `/provider`. Basic auth as `opencode` with a password generated once into `~/.local/state/opencode/server-password`; the bridge hands the port and password to the app under `code` in `/api/config` |
| 6688 | `phone-bridge` (user) | `GET /api/config` (desktop ip, ports, hub manifest, the opencode server's port and password); `GET/POST /api/volume` (default sink, all sinks, set level, mute, default); `GET/POST /api/lease`, `POST /api/lease/position` (who plays, where, since); `GET /api/lyrics?file=` (`.lrc` beside the track, then the `~/Music/.lyrics` cache, then lrclib, writing the `.lrc` when synced lyrics exist); `GET /api/now`; `GET /api/cover?file=` (the picture mpd reads from the file, `readpicture` then `albumart`, 404 when there is none); `GET /api/money` (the money-menu cache plus `stale` and `refreshing`), `POST /api/money/refresh` (starts the `money-menu-refresh` user unit); `GET /api/hub` (the hub manifest plus untiled hosts and per-host state from status.mvr.ac, the VPS stats, the desktop's gpu-status; merged on the desktop and cached 20 s so the phone never leaves the tailnet); `GET /api/app` (the build `phone-push` last published: `versionCode`, `versionName`, `sha256`, `size`), `GET /api/app/apk` (that build, as a download); `GET /api/load` (memory, cpu and io pressure from `/proc/pressure`, free memory and swap, and the eight heaviest user units by memory plus swap with the name of their largest process, read straight from the cgroup tree so it answers while the desktop thrashes); `POST /api/kill {"id"}` (kills that unit's whole cgroup through `cgroup.kill`; the compositor, audio, dbus, the portals and the bridge itself are never listed or killable); `GET /api/media` (the desktop's other MPRIS players through `playerctl`, mpd excluded: name, status, title, artist, url, and "YouTube" as the source when the url says so), `POST /api/media {"player","action"}` (play-pause, play, pause, next, previous on that player) |
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
  on pause: the desktop always knows where the phone is. The body names the
  song (file, title, artist, duration), not only the file; a heartbeat that
  changes the file without them makes the bridge read the tags from mpd's
  database, so the lease never describes one song with another's name.
- `POST /api/lease {"owner":"desk"}`: mpd plays the recorded file from the
  recorded second (inserted right after the current song if it is not in the
  queue), paused if the phone was paused.
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
4. **Wireless debugging**, only for `phone-syncthing-bootstrap` above and as
   the fallback install path: Developer options → Wireless debugging → pair
   with code once from the desktop (`adb pair <ip:pairport>`), then
   `adb connect <ip:port>`; the port changes per session, read it off the
   screen. `~/Projects/android-music-sync/setup_adb.sh` has the walkthrough.
   Turn it off again afterwards; nothing below needs it.
5. **The app**: `phone-push` on the desktop builds it and publishes it to the
   bridge. First install: open `http://<desktop tailnet ip>:6688/api/app/apk`
   in the phone's browser, open the download, allow installs from the browser
   once, install. Every later build is offered by the app itself: a line on
   home reads "update ready" when the desktop holds a newer build; one tap
   downloads it over the tailnet, checks it against the bridge's hash and
   hands it to Android's installer, which asks once to allow installs from
   the app and then once per update. `PHONE_ADB_ADDR=<ip:port> phone-push`
   still installs over wireless debugging instead of publishing.

## The app: every tap

The UI is this table. A row is struck or rewritten before the code changes,
and the on-device check is the table read top to bottom. Ground rules: music
plays in exactly one place; opening the app changes nothing anywhere; the
desktop owns playback unless the phone is actually playing, and play in
ncmpcpp takes it back; handing music back never rewrites mpd's queue; no
pop-ups, errors sit on one reserved line under the pill.

| State | The screen shows | Taps act on |
|---|---|---|
| desktop owns | mpd's current song, position, play state | mpd, the queue ncmpcpp shows |
| phone owns | the phone's current song | the phone's queue: the copy taken from mpd when the music moved (taken again when the app comes back mid-lease), minus files not synced |
| nobody playing | the last song wherever the pill points, paused | that side |
| desktop unreachable | banner under the header; slider and desktop side greyed | the phone only |

Home, three live cards (chosen on 2026-11-14 from the deck of three
directions: a card opens into its screen, the chevron on the title or Android
back collapses it):

| Tap | Does | Lands |
|---|---|---|
| music card: play / pause (left) | toggles the owner, exactly as on the music screen | home |
| music card: the desktop media line ("<title> · YouTube on the desktop"), shown only while another player on the desktop has something | pauses or resumes that player, like KDE Connect's media control | home |
| music card: volume slider / speaker | desktop system volume, music or not | home |
| music card: name, cover, title | opens the music screen | music |
| money card: the total | cycles the unit BTC → USD → BRL (the phone's own unit) | home |
| money card: name | opens the money screen | money |
| hub card: name or glance | opens the hub screen | hub |
| code card: a session row | opens that session on the code screen | code |
| code card: name | opens the code screen on the last session, or a new one when there is none | code |
| code card: "new session" | opens the code screen on an empty session in the last used directory | code |
| panic card: name or the gauge | opens the panic screen | panic |
| panic card: "kill the biggest", first tap | arms it for 4 s; the button reads "tap again to kill <name>" | home |
| panic card: "kill the biggest", second tap | kills that unit's whole cgroup on the desktop; the card says what died | home |
| "update ready" line (only when the desktop published a newer build) | downloads it, verifies the hash, opens Android's installer; the first time it opens the "allow installs from this app" setting instead and says so on the notice line | installer |
| header dot | nothing, display | home |
| Android back on home | leaves the app | launcher |
| title chevron or Android back, on any sub-app | collapses to home | home |

The music screen:

| Tap | Does | Lands |
|---|---|---|
| drag the desktop volume slider | moves the desktop's system volume live, music or not | same screen |
| speaker icon | mutes / unmutes the desktop | same screen |
| cover | lyrics replace the cover; tap again brings the cover back | same screen |
| drag the seek bar | seeks whoever owns playback | same screen |
| prev / next | previous or next song in the owner's queue, as in ncmpcpp | same screen |
| repeat icon, left of prev | cycles off → all → one for both sides at once: it sets mpd's repeat and single flags, which the phone's own queue follows; with the desktop unreachable it applies to the phone until mpd is back | same screen |
| play / pause | toggles the owner; with nothing playing, resumes the last song where the pill points | same screen |
| "next ·" line | nothing, display only | same screen |
| pill, the other side | moves the music there at the same second; the old side pauses | same screen, pill moved |
| pill, the side it is on | nothing | same screen |
| pill to phone, file not synced | error line "not on the phone yet", nothing moves | same screen |
| pill to desktop, unreachable | error line "desktop unreachable", nothing moves | same screen |
| the desktop media line under the pill | pauses or resumes that desktop player (a browser's YouTube tab, mpv); absent when nothing but mpd plays | same screen |
| "play something" | the sheet slides up with the keyboard open | the sheet |
| "music ⌄" title | collapses to home | home |
| Android back | collapses to home | home |

The "play something" sheet:

| Tap | Does | Lands |
|---|---|---|
| type | filters the library live by tags and path; newest first when empty | sheet |
| a song | plays it now on the side the pill points, inserted right after the current song | music screen |
| a greyed song (pill on phone, not synced) | nothing | sheet |
| scrim, swipe down, Android back | closes | music screen |

The money screen (the waybar money-menu and its rofi popup, ported; unit and
hidden amounts are the phone's own, remembered across restarts):

| Tap | Does | Lands |
|---|---|---|
| the total | cycles the unit | money |
| BTC / USD / BRL chip | sets the unit | money |
| eye | hides amounts (digits → •), remembered | money |
| refresh | starts `money-menu refresh` on the desktop; the line reads "refreshing…" until a newer fetched_at arrives | money |
| "by asset" / "by venue" chips | groups the holdings by asset across venues (the default) or by venue; remembered | money |
| an asset or venue row | collapses / expands its lines | money |
| "fetched … ago" line | nothing; amber with "stale" past 20 min; "desktop unreachable · last known values" offline | money |

The hub screen (hub.mvr.ac, ported; the click counts that sort the rows are
the phone's own, since the hub's own counter sits behind authelia):

| Tap | Does | Lands |
|---|---|---|
| the status summary | expands / collapses the desk card, vps card and "needs attention" | hub |
| a service row | opens its url (`url` or `https://host`) in the browser; the tap counts for sort-by-use on this phone | browser |
| "no tile" tag, lock badge, state dot | nothing, display | hub |

The code screen (opencode on the desktop, driven over its HTTP API and event
stream; the same sessions the desktop's `oc` tui attaches to. The transcript is
coloured by meaning the way `salcc` colours a terminal, with its heuristics
ported: destructive commands and irreversible words red and bold, shell
commands mono, sentences that tell the operator to do something in the
tertiary colour, hedged clauses dim italics, narration dimmed. Tool calls are
one line each, reasoning is folded):

| Tap | Does | Lands |
|---|---|---|
| the session title / folder line | opens the sessions sheet: "new session in" every project the server knows, then recent sessions newest first, working ones marked | sheet |
| a session in the sheet | loads its transcript and follows it live | code |
| a project under "new session in" | an empty session there; it is created on the first message | code |
| the model chip | cycles the connected providers' default models; remembered on this phone | code |
| type, then send | sends to the session (creating it first when new); the reply streams in as it is written | code |
| send while it works | queues the message behind the current turn | code |
| stop (replaces send while it works and the box is empty) | aborts the current turn | code |
| a tool line | expands its command or file and its output; again collapses | code |
| "thinking · n lines" | expands the model's reasoning; again collapses | code |
| a permission card: once / always / reject | answers the agent's permission request; the card leaves when the server confirms | code |
| a question card: an option | answers a single-choice question at once; with several choices or several questions the options toggle and "answer" sends | code |
| a question card: skip | rejects the question | code |
| "code ⌄" title or Android back | collapses to home | home |

The panic screen (what is grinding the desktop, and the way to stop it; the
list is the eight heaviest user units by memory plus swap, named after their
largest process, refreshed every 3 s while the screen is open and every 10 s
from home):

| Tap | Does | Lands |
|---|---|---|
| "kill the biggest", first tap | arms it for 4 s; reads "tap again to kill <name>" | panic |
| "kill the biggest", second tap | kills the top unit's whole cgroup; "killed <name>" appears under the list | panic |
| a row's "kill", first tap | arms that row for 4 s; the row turns red and reads "tap again" | panic |
| a row's "kill", second tap | kills that unit's whole cgroup | panic |
| anything else on a row, the gauges | nothing, display | panic |
| leaving the screen | disarms whatever was armed | home |

Lock screen and notification: prev / play / next act on the owner; the body
opens the app on the music screen; volume keys follow the pill (desktop side moves the desktop's
volume, phone side the phone's); the subtitle reads "artist · on the
desktop" or "artist · on the phone". No move button on the lock screen.

Not now: ytdl client, sync status, share target, Claude inside the code screen (needs an API key; see the backlog). They get a card and a table
here when they come.

## Trying the app on the desktop

`phone-emu` runs the real APK in the Android emulator so the app can be
used, not looked at: tap, go back, lock the virtual phone, press its volume
keys. The first run creates a virtual device (Android 35, the phone's 1080×2400
screen) under `~/.local/share/mandragora-phone/`, boots it, builds the debug
APK unless `PHONE_APK` names one, installs it, grants notifications and music
access, pushes the song mpd is on plus the twelve newest files from `~/Music`
into the device's Music folder so the phone side has something to play, and
opens the app. Later runs reuse the booted device. The build signs with the
same debug key `phone-push` uses (`~/.android/debug.keystore`, copied into the
emulator's user home on every run), so a build from either tool installs over
the other; an app on the device signed with any other key is uninstalled and
installed afresh. The emulator reaches the
desktop's tailnet address through the host, so the volume bar, the pill and
"play something" act on the real mpd and the real sink; use it the way the
phone would be used, music included. Rendering is software by default
(`PHONE_EMU_GPU=host` for the GPU), and the window is an X11 window under
Hyprland; `PHONE_EMU_HEADLESS=1` boots it with no window and no audio, for
checks driven over adb while nobody is looking.

## The icon

The launcher icon is the two-tone sprout chosen on 2026-11-15 and it follows
the desktop's wallpaper: twelve hue variants are compiled in as
`activity-alias` entries and the app enables the one nearest the live
palette's primary hue whenever it leaves the foreground. `app/icon/README.md`
has the mechanism, the generator and the candidate pages from the three
rounds, for the next time the icon changes.

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
- Versions: `versionCode` is the build's minute since the epoch, so every
  build is newer than the one before and Android never sees a downgrade;
  `versionName` is `git describe --always --dirty`, so the update line and
  the installed app name the commit they came from.
- Publishing: `phone-push` copies the APK and an `app.json` (version, sha256,
  size) into `~/.local/share/mandragora-phone/app/`, atomically, APK first;
  the bridge serves both. The emulator's `phone-emu` installs over adb and
  does not touch the slot.

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
