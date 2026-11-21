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
| Sync-Fork (`com.github.catfriend1.syncthingandroid`) | Music receive-only and the Notes folder send-receive; the six photo inbox folders left it on 2026-11-21 for the app (below), and any still listed on the phone are unshared leftovers that sync nothing | `identity.json`, `nix/modules/desktop/syncthing.nix`, `phone-syncthing-bootstrap` |
| KDE Connect | clipboard, notifications, trackpad, system volume fallback | `nix/modules/desktop/kdeconnect.nix` |
| the stock calendar app | the Google and the Hotmail calendar, each signed in on the phone as its own account; the desktop syncs the same two | the accounts themselves; desktop side in [`docs/calendar.md`](../../../docs/calendar.md) |
| Obsidian | the notes vault, opened from `Documents/notes` | the Notes folder above; `.config/syncthing/notes.stignore` |
| DroidCam | mjpeg for the kindle camera widget | `nix/modules/services/kindle-cam.nix` |
| mandragora (this repo's app) | one screen: desktop volume, the pill that moves the music, the song, "play something" (the find screen); with *All files access* on, it is also the desktop's way into the phone's photos and videos (below) | `app/` |

## What the desktop serves for it

All of it on the tailnet interface only; nothing here has a `*.mvr.ac` host.

| port | unit | what |
|---|---|---|
| 4097 | `claude-bridge` (user) | Claude Code sessions over the same API shape as opencode's: `GET /project` and `GET /session?directory=` from the on-disk session store (each session with the `providerID` and `modelID` that answered last, read from the transcript's tail), `GET /session/:id/message`, `POST /session` (a fresh id the first prompt will create), `prompt_async`, `abort`, the `/event` stream, `/permission` and `/question` with their replies, `PATCH` rename (typed into the pane as `/rename <title>` for a session open on the desktop, unless it waits on a dialog; written to the transcript otherwise), `DELETE`, `fork`, `POST /session/:id/close` (ends the session's `claude` on the desktop, checked against the start time the session index records so a reused pid is never hit, or stops the run the bridge holds; `false` when nothing was open), and `GET`/`POST /session/:id/settings` (model, effort and permission mode per session, kept in `~/.local/state/claude-bridge/choices.json`; for a session open in a desktop tui, read from its pane and set through its own controls). A Claude or DeepSeek session that is not open anywhere opens in a new tmux window on the desktop when the phone sends to it, so it can be picked up at the desk: `claude` or `deepseek` with `--session-id` for a new session and `--resume` for an old one, in that session's own folder, with the chosen model, effort and permission mode, in the tmux session with the latest client activity and without switching to it (a fresh `claude` tmux session when none is running, started outside the bridge's cgroup); the message is typed in once its input box is up, and from then on it is a desktop session like any other, so a restart of the bridge no longer ends it. Only a local model still runs as `claude -p` through the Agent SDK inside the bridge, through Ollama's own Anthropic-compatible endpoint (`local`: `cc-qwen3.6` and `cc-gptoss`, 64k-context variants of the declared `coder` and `agentic` models that the bridge makes in Ollama on first use; each turn holds the gpu lock, a busy GPU answers 409 with the holder, and the model is evicted a minute after the turn), chosen per session (a session the bridge already runs headless keeps running there until it idles out); sessions open in a desktop tui are listed with their name and state, and a message to one is typed into its tmux pane, since resuming it would start a copy; `GET /screen` and `POST /session/:id/screen` mirror the dialog such a session waits on (read with `tmux capture-pane` while the session index says `waiting`, answered with `send-keys`). Basic auth as `claude`, password generated once into `~/.local/state/claude-bridge/server-password` |
| 4096 | `opencode-serve` (user) | the opencode HTTP server, the one the desktop `oc` tui attaches to: sessions, messages, `prompt_async`, `abort`, the `/event` stream, permission and question replies, `/project`, `/provider`. Basic auth as `opencode` with a password generated once into `~/.local/state/opencode/server-password`; the bridge hands the port and password to the app under `code` in `/api/config` |
| 6688 | `phone-bridge` (user) | `GET /api/config` (desktop ip, ports, hub manifest, the code backends — claude-bridge and opencode — with port, user and password); `GET/POST /api/volume` (default sink, all sinks, set level, mute, default); `GET/POST /api/lease`, `POST /api/lease/position` (who plays, where, since); `GET /api/lyrics?file=` (`.lrc` beside the track, then the `~/Music/.lyrics` cache, then lrclib, writing the `.lrc` when synced lyrics exist); `GET /api/now`; `GET /api/file?file=` (a song from the library, with byte ranges, so the phone can stream what Syncthing has not delivered yet); `GET /api/cover?file=` (the picture mpd reads from the file, `readpicture` then `albumart`, 404 when there is none); `GET /api/money` (the money-menu cache plus `stale` and `refreshing`), `POST /api/money/refresh` (starts the `money-menu-refresh` user unit); `GET /api/hub` (the hub manifest plus untiled hosts and per-host state from status.mvr.ac, the VPS stats, the desktop's gpu-status; merged on the desktop and cached 20 s so the phone never leaves the tailnet); `GET /api/app` (the build `phone-push` last published: `versionCode`, `versionName`, `sha256`, `size`), `GET /api/app/apk` (that build, as a download); `GET /api/load` (memory, cpu and io pressure from `/proc/pressure`, free memory and swap, and the eight heaviest user units by memory plus swap with the name of their largest process, read straight from the cgroup tree so it answers while the desktop thrashes); `POST /api/kill {"id"}` (kills that unit's whole cgroup through `cgroup.kill`; the compositor, audio, dbus, the portals and the bridge itself are never listed or killable); `GET /api/media` (the desktop's other MPRIS players through `playerctl` that are playing or paused, mpd excluded and so are the mirrors KDE Connect and playerctld make of players that are not the desk's own: instance name, status, title, artist, url, position and length in seconds, an artwork key, and "YouTube" as the source when the url says so), `GET /api/media/art?player=` (that player's artwork when it is a local image file, as Firefox writes one per video), `POST /api/media {"player","action"[,"position"]}` (play-pause, play, pause, next, previous, or seek to `position` seconds on that player); `POST /api/transcribe` (raw audio, `audio/mp4`, passed to the desktop's `stt-core`, faster-whisper on the GPU, which knows English and Portuguese; answers `{text, language, duration}`, or 503 with the reason when the GPU is busy or the service is down; `?task=translate` gives English and `&language=` skips detection); the phone's photos and videos, all under `~/.local/state/phone-bridge/phone-media/`: the app posts its MediaStore listing to `POST /api/phone/media/index` (whenever it changed, and every six hours anyway) and reads its queue from the answer or `GET /api/phone/media/jobs`, uploads a thumbnail to `POST /api/phone/media/thumb?id=`, a file to `POST /api/phone/media/file?id=` with its sha256 in `X-Sha256` (kept under `held/` only when the bytes hash to it), and reports each job's outcome to `POST /api/phone/media/report` (a deletion is logged in `removed.jsonl`; a failure leaves the queue and is listed, so nothing retries forever); the desktop side is `GET /api/phone/media` (index, queue, held copies, failures, when the phone last checked in), `POST /api/phone/media/request {thumbs, pull, remove}` (a deletion is refused until the desktop holds a verified copy, and carries that copy's sha256, which the phone re-hashes before it deletes), `GET /api/phone/media/thumb?id=`, `GET /api/phone/media/held?id=` and `POST /api/phone/media/release {ids}`; `POST /api/phone/media/request {archived: {id: sha256}}` queues a deletion for something the desktop archived elsewhere. Only the phone's tailnet ip (from `tailnet.json`, or `PHONE_BRIDGE_MEDIA_PEERS`) may post an index, fetch jobs, upload or report, so an emulator running the app against the desk cannot stand in for the phone; the jobs answer says `reindex` when the bridge holds no index. `phone-media` (`status`, `ls`, `sheet`, `move ID… --to DIR [--keep]`, `archive`) drives it from a shell; the `phone-media-archive` timer runs `archive` every 10 min: everything in the six drained folders (DCIM, Pictures, Movies, WhatsApp media, Recordings, Download, minus what the old Syncthing ignore list skipped) is copied into `~/Pictures/PhoneInbox/<bucket>/…`, where `phone-archiver` files it by date at once, and an item is deleted from the phone once it is 30 days old and its sha256 is found, re-hashed, in the archive; `GET /api/stt/status`, `POST /api/stt/warmup` (stt-core's own, passed through, since its port stays off the tailnet); `GET /api/inbox?after=&wait=` (long poll, up to 50 s), `POST /api/inbox` (`{source, title, text, open, link, level: info or alert, ref}`, what `mandragora-notify`, watch and the tutor send; the newest 300 kept in `inbox.json`), `POST /api/inbox/read {upTo}`, `POST /api/inbox/drop {id}` or `{upTo}`; `/api/watch/<api path>` (any method, forwarded to watch.mvr.ac's tailnet-only `/internal/` route, so the phone needs no Authelia session) |
| 6689 | `phone-ask` (user) | the local model and the desktop's shell for the ask screen, the retired llm-via-telegram bot's whole surface: `GET /api/ask?after=&wait=` (long poll: the timeline after an id, busy, the model, thinking on or off, the personas and the registered commands), `POST /api/ask {text}` (plain text goes to the model, a slash command runs in the server), `POST /api/ask/stop`, `POST /api/ask/think {on}`. Tools, system prompt (AGENTS.md and `docs/local-llm.md`), gpu lock and history work as the bot did; state in `~/.local/state/phone-ask` |
| 6691 | `teacher-teach` (user) | the Socratic tutor from `~/Projects/teacher` (`teacher.server`), the retired Telegram tutor: `GET /api/teach?after=&v=&wait=` (long poll on a version), `POST /api/teach/say {text}`, `POST /api/teach/act {action: warmup, long, done, answer, explain; concept}`, `GET /api/teach/stats`, `POST /api/teach/retention {topic, value}`, `POST /api/teach/nudge {enabled}`, `POST /api/teach/retry`; nudges go to the inbox |
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
   It sets up Notes and Music only; photos reach the desktop through the app.
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
| music card: the desktop media line ("<title> · YouTube on the desktop"), shown only while another player on the desktop has something | pauses or resumes that player, like KDE Connect's media control; resuming it pauses the music first | home |
| music card: volume slider / speaker | desktop system volume, music or not | home |
| music card: name, cover, title | opens the music screen | music |
| money card: the total | cycles the unit BTC → USD → BRL (the phone's own unit) | home |
| money card: the share bars | nothing, display; one bar per asset, assets under one percent folded into one, or per venue when the money screen is set to venues | home |
| money card: name | opens the money screen | money |
| hub card: name or glance | opens the hub screen | hub |
| code card: a session row (only the active ones: every session open on the desktop, working or waiting for you, newest first; with none, the card says "nothing open on the desktop" and the chevron still opens every session; a row is the dot, the model's mark, the title, red when the session needs you, and the last words of the transcript; no subtitle line) | opens that session on the code screen | code |
| the dot on a session row | nothing, display: green when the session is open on the desktop, pulsing in the accent while it works, hollow when it is closed | home |
| the mark on a session row | nothing, display: who answered last, in its brand color: Claude's starburst, DeepSeek's whale, Qwen or OpenAI for the two local models, Ollama for another local one, opencode's square for an opencode session; an empty gap when the bridge does not know. The same mark leads the model chip on the code screen and each model in the session sheet | home |
| a session row, swiped to the left (only a Claude Code session that is open on the desktop or working; the others do not move) | a red strip with "close" follows the finger; past two fifths of the row it fills, buzzes once and reads "let go to close", and letting go there (or a fast flick past a third of that) closes the session: the row turns into "closing on the desktop in 5 s" with a draining line and an "undo" chip, and only when the five seconds run out does `claude-bridge` end that session's `claude` (SIGTERM, then SIGKILL after 6 s if it is still there). A window the phone opened goes away with it; a `claude` started from a shell leaves that shell. A working session says "its turn stops" while it counts down; once the five seconds are up the undo goes away and the row reads "closing on the desktop…" until the bridge answers. The transcript stays, so the next message opens it again. Let go short of the line and the row springs back. The same swipe works in the sessions screen and the sessions sheet | home |
| code card: name or chevron | opens the sessions screen: every Claude Code session, searchable like `claude-find` | sessions |
| code card: "new session" | opens the code screen on an empty session in the last used directory | code |
| panic card: name or the gauge | opens the panic screen | panic |
| panic card: "kill the biggest", first tap | arms it for 4 s; the button reads "tap again to kill <name>" | home |
| panic card: "kill the biggest", second tap | kills that unit's whole cgroup on the desktop; the card says what died | home |
| inbox card: name or a line | opens the inbox screen; the subtitle is "n new", "listening" or "not listening" | inbox |
| voice card: name | opens the voice screen | voice |
| ask card: name or the last reply | opens the ask screen; the subtitle is the model, or what it is doing | ask |
| teach card: name or the last line | opens the teach screen; the subtitle is the streak, what is due and how often you were right, or that the tutor is writing | teach |
| watch card: name or a trigger | opens the watch screen; the subtitle counts the triggers not yet accepted | watch |
| "update ready" line (only when the desktop published a newer build) | asks the desktop for its current build first, then downloads it, verifies the hash, opens Android's installer (a build published while the line was showing is the one installed); the first time it opens the "allow installs from this app" setting instead and says so on the notice line. The verified download is kept, so leaving the app mid-download never costs a second one: the line turns into "install update", and a download that finishes while the app is in the background posts a "tap to install" notification instead of opening the installer | installer |
| header dot | nothing, display, a dot with no words (the banner under the header says what is wrong): green when the desktop answers; hollow from the moment the app opens until the first answer, with retries a second apart; red only after three misses in a row, and from then on a retry every five seconds | home |
| gear in the header | opens settings | settings |
| Android back on home | leaves the app | launcher |
| title chevron or Android back, on any sub-app | collapses to home | home |

The settings screen (the first one; card order is the phone's own, like
the money unit and the hub's click counts):

| Tap | Does | Lands |
|---|---|---|
| ▲ / ▼ on a card row | moves that card one step on home, saved at once; the update line always stays on top | settings |
| "next and prev start playback" switch | on (the default): a skip while paused plays the new song, on either side; off: a skip while paused stays paused; a skip while playing always keeps playing | settings |
| "squash call chains" switch | on (the default): two or more tool calls in a row show on the code screen as one "n calls" line; off: every call and every thinking block gets its own line, as before | settings |
| "the desktop reaches photos and videos" switch | opens Android's *All files access* page for the app, either way; the line under it says whether it is on and when the app last reached the desktop. While it is on, the app syncs with `phone-bridge` every 10 s while open and every 15 min in the background (a persisted JobScheduler job, no notification): it posts its index when it changed, then makes the thumbnails, copies and deletions the desktop queued | settings |
| "listen in the background" switch | on (the default): a foreground service keeps a long poll to the bridge's inbox and turns each new item into an Android notification, alerts in a channel of their own; off: items wait in the inbox until the app opens | settings |
| "battery is restricted" (only while listening and the app is not exempt) | opens Android's request to let the app ignore battery optimisation, so the listener survives sleep | Android |
| "settings ⌄" title, Android back | collapses to home | home |

The sessions screen (every Claude Code session on the desktop, the way
`claude-find` finds them; the bridge keeps that index fresh and runs its
full-text search):

| Tap | Does | Lands |
|---|---|---|
| empty box | every session, latest activity first, with its dot and title | sessions |
| "hide closed" / "+n closed" (right of the count) | hides or shows again the sessions that are neither open on the desktop, working nor waiting for you; shown each time the screen opens, since the code card already lists only the active ones and this screen is the only place a closed session can be found; never remembered, and it applies to search results too | sessions |
| type | full-text search over every session's turns, a phrase or subject; each row shows the matching passage | sessions |
| a session | opens it on the code screen | code |
| a session, swiped to the left | closes it on the desktop after five seconds with an undo, as on the code card | sessions |
| "sessions ⌄" title, Android back | back to home | home |

The music screen:

| Tap | Does | Lands |
|---|---|---|
| drag the desktop volume slider | moves the desktop's system volume live, music or not | same screen |
| speaker icon | mutes / unmutes the desktop | same screen |
| cover | lyrics replace the cover; tap again brings the cover back; a song with no cover shows its lyrics in that place instead, and no placeholder art anywhere | same screen |
| drag the seek bar | seeks whoever owns playback | same screen |
| prev / next | previous or next song in the owner's queue, as in ncmpcpp; whether a skip while paused starts playback is the "next and prev start playback" setting | same screen |
| repeat icon, left of prev | cycles off → all → one for both sides at once: it sets mpd's repeat and single flags, which the phone's own queue follows; with the desktop unreachable it applies to the phone until mpd is back, and is then sent to mpd once, after which the app follows mpd again (a change made in ncmpcpp shows here) | same screen |
| play / pause | toggles the owner; with nothing playing, resumes the last song where the pill points; after the phone's queue has run out it plays the last song again from the start | same screen |
| a phone song that fails to play (the stream breaks, the desktop answers an error, the file does not decode) | nothing to tap: the notice line says "skipped <song> · <why>" and the next playable song starts; with nothing playable left, or after five failures in a row, it pauses on "can't play <song> · <why>". A song that is neither on the phone nor reachable is skipped the same way | same screen |
| "next ·" line | nothing, display only | same screen |
| pill, the other side | moves the music there at the same second; the old side pauses | same screen, pill moved |
| pill, the side it is on | nothing | same screen |
| pill to phone, file not synced | the phone streams the file from the desktop over the tailnet (`/api/file`, with byte ranges so seeking works) and plays it from the same second; only with the desktop unreachable does it refuse, "not on the phone and the desktop is unreachable" | same screen |
| pill to desktop, unreachable | error line "desktop unreachable", nothing moves | same screen |
| the desktop media line under the pill | pauses or resumes that desktop player (a browser's YouTube tab, mpv); resuming it pauses the music first; absent when nothing but mpd plays | same screen |
| "play something" | opens the find screen with the keyboard up | find |
| "music ⌄" title | collapses to home | home |
| Android back | collapses to home | home |

The find screen (one box answered in facets, chosen on 2026-11-15 from a
deck of five; the library's tags are read once when the screen opens and
again on a later open, so everything below runs on the phone):

| Tap | Does | Lands |
|---|---|---|
| type | filters live across title, artist, album, genre, year and path; every word must match; the match is highlighted and a row says what matched when it was not the title, artist or album | find |
| empty box | newest songs, the top artists and the top albums | find |
| an artist row | narrows to that artist as a crumb and clears the box | find |
| an album row | narrows to that album by that artist as a crumb (albums of the same name by different artists are separate rows) | find |
| the crumb | widens again | find |
| "N in all" / "fewer" on a section | shows every artist or album that matched, or the top few again | find |
| a sort chip (newest · title · artist · album · year · longest) | reorders the songs | find |
| a song | plays it now on the side the pill points, inserted right after the current song | music screen |
| a greyed song (pill on phone, not synced, desktop unreachable) | nothing; with the desktop reachable no song is greyed, the ones not synced stream | find |
| "find ⌄" title, Android back | back to the music screen | music screen |

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

The code screen (coding-agent sessions on the desktop, driven over one HTTP
and event API with two backends behind it: `claude-bridge`, which runs Claude
Code with Claude or DeepSeek and lists the same sessions the desktop's `claude`
tui has, and `opencode-serve`, the sessions the `oc` tui attaches to. The transcript is
coloured by meaning the way `salcc` colours a terminal, with its heuristics
ported: destructive commands and irreversible words red and bold, shell
commands mono, sentences that tell the operator to do something in the
tertiary colour, hedged clauses dim italics, narration dimmed. Tool calls are
one line each, reasoning is folded):

| Tap | Does | Lands |
|---|---|---|
| the session title (whole, on as many lines as it needs; session rows show the whole title too) | turns into an edit box holding the whole name, cursor at the end; ✓ or the keyboard's Done renames the session, ✕ or Android back leaves it as it was. A session open on the desktop is renamed through its own `/rename`, which Claude Code runs at once, mid-turn too, and records as a user-set title; a closed one gets the title written to its transcript; an opencode session through opencode's rename. Before a new session exists the title reads "new session" and the tap opens the sessions sheet instead | code |
| "new session" (the title, only before a session's first message) | opens the sessions sheet: "new session in" every project the server knows, then recent sessions newest first, working ones marked. An open session has no way into the sheet; another session is opened from the code card or the sessions screen | sheet |
| a session in the sheet | loads its transcript and follows it live | code |
| a session in the sheet, swiped to the left | closes it on the desktop after five seconds with an undo, as on the code card | sheet |
| a project under "new session in" | an empty session there; it is created on the first message | code |
| the session chip (model · effort · mode, right of the title) | opens the session sheet; the chip names the model, the effort when one is set, and the mode | sheet |
| session sheet: a model | claude (your default), fable, opus, sonnet, haiku, deepseek pro, deepseek flash, local qwen3.6, local gptoss (all Claude Code), opencode · deepseek; a Claude Code session is offered every Claude Code model and an opencode session only opencode's; a model of the kind the session already runs takes effect from the next turn without restarting it, and another kind restarts it with the conversation kept (see the next row for a desktop session); the last pick is what a new session starts with | sheet |
| session sheet: an effort | default (what the desktop's settings say), low, medium, high, xhigh, max; applied to the running session at once | sheet |
| session sheet: a mode | auto (a classifier approves or refuses each tool call), ask, accept edits, plan; every session started from the phone starts in auto; applied to the running session at once; approving a plan returns it to the mode it had before | sheet |
| session sheet, on a session open on the desktop (green dot) | the same model, effort and mode choices, for that session only: `claude-bridge` works the terminal's own controls in its tmux pane (shift+tab for the mode; the model picker, alt+p, for model and effort, confirmed with its "use this session only" key), so the desktop's defaults stay as they are; a model of another kind (claude, deepseek or local, which differ in the terminal's environment) ends that terminal's `claude` and continues the conversation on the new one: claude and deepseek reopen it at once in a new tmux window, a local model runs it headless inside the bridge from the next message, since the bridge holds the gpu lock turn by turn and can only do that for a process it drives (sending to it with claude or deepseek later brings it back to a tmux window); refused while the terminal waits on an answer, works on a turn, or runs a background command, since ending it there would lose that work | sheet |
| a session open on the desktop (green dot) | opens it and follows it live: `claude-bridge` watches the transcripts of sessions it does not run itself and pushes a change within about a second, so anything said in the desktop tui or the Claude app appears without reopening | code |
| type, then send | sends to the session (creating it first when new); the reply streams in as it is written | code |
| the paperclip left of the box | a menu: "a picture" or "a file or pdf"; both pick several at once | code |
| "a picture" | opens the phone's photo picker; each picture is shrunk to 2048 px, uploaded to `claude-bridge` (kept under `~/.cache/claude-bridge/uploads`) and shown as a thumbnail with a remove cross; send adds a line per picture naming its path, which Claude Code opens with its Read tool; the bubble shows the picture (or a "picture" chip once the app has restarted) instead of the path | code |
| "a file or pdf" | opens the phone's file picker on any type, up to 30 MB each; a picture picked here goes the picture way, anything else is uploaded as is under its own name and shown as a chip with its name and a remove cross; send adds a line per file naming its path, read the same way (Claude sees a pdf's pages; DeepSeek gets its text through `pdftotext`, which is on the bridge's path for that) | code |
| the transcript | shows the whole conversation like the terminal does, across context compactions, with a thin "earlier context was summarized here" line where each happened; follows new messages and replies while it is at its newest end; scrolled up to read, it stays where it is | code |
| a message just sent | shows at once as a faded bubble, "queued · goes in when the current turn ends" while the session works, "sent · waiting for the session" otherwise, and gives way to the real message when it reaches the transcript | code |
| type, then send, on a session open on the desktop (green dot) | types the message into that session's tmux pane, as a bracketed paste followed by Enter, so the desktop tui runs it as if typed there; a session outside tmux answers "send from there" on the error line above the box | code |
| send while it works | queues the message behind the current turn | code |
| stop (replaces send while it works and the box is empty) | aborts the current turn; on a session open on the desktop (green dot) it presses Esc in its tmux pane, and when the tui puts the stopped prompt back in its input box (it does when no reply has been written yet) clears it with one Ctrl+C, so the next message from the phone is not typed after it | code |
| the microphone (replaces send while the box is empty, nothing is attached and nothing is working) | records; the attach button becomes ✕ and the box reads "listening · 0:07 · ✓ sends it". ✓ stops, the desktop's `stt-core` transcribes it through the bridge (a spinner meanwhile; the first one after a while loads the model, about ten seconds), and the words go out as the prompt. ✕ drops the recording. Asks for the microphone the first time; a GPU busy elsewhere or a recording too short says so on the error line | code |
| a stopped turn | its message is marked "stopped" with a "resend" chip: the turn the transcript records as interrupted, or the last message when the session is idle and nothing answered it; only the newest stopped turn carries the chip | code |
| "resend" | sends that message again, pictures and files included, without touching what is in the box | code |
| press and hold a message you sent | a menu: copy (the words), edit, and resend when that turn was stopped | code |
| edit (in the hold menu) | puts the message and its pictures and files in the box with the cursor at the end, for sending as a new message; the turn already in the transcript stays | code |
| press and hold a reply | a menu with copy, which copies the whole reply's text as markdown | code |
| a reply's text | nothing; it is set in Source Serif 4, the open serif closest to the Claude app's reply face, and renders as markdown (headings, bold, italics, lists, quotes, links, inline code, code blocks that scroll sideways) with the colour markers and the salcc colouring kept; a table is a grid whose short columns never wrap, whose wordy columns wrap at a readable width, and which scrolls sideways as one with its first column pinned when it has three or more columns (chosen on 2026-11-17 from a deck of five) | code |
| a tool line | expands its command or file and its output; again collapses | code |
| "n calls · Bash ×4 · Edit ×2" (two or more calls in a row, across messages, with the thinking between them; text the model wrote breaks the run; only while "squash call chains" is on) | expands into the tool lines and thinking lines it stands for; again collapses. While the run is still going, the call in flight shows under it | code |
| "thinking · n lines" | expands the model's reasoning; again collapses | code |
| a permission card: once / always / reject | answers the agent's permission request; the card leaves when the server confirms | code |
| a question card: an option | answers a single-choice question at once; with several choices or several questions the options toggle and "answer" sends | code |
| a question card: skip | rejects the question | code |
| a session marked "needs you" (red) | it is waiting for an answer: a permission, a question or a finished plan; the home card counts them; opening it shows the prompt card at the bottom | code |
| a desktop prompt card: an option | a session open on the desktop that stops to ask shows the same choices here, read off its tmux pane; a tap presses that option's number in the pane, so the desk and the phone answer the same dialog and whichever is first wins; a tap on a prompt that has already changed on the desk is refused and the new one shown | code |
| a desktop prompt card: an option that takes words ("Type something", "Tell Claude what to change") | opens a line to type in; send presses the number, types the words and Enter | code |
| a desktop prompt card: ‹ back / next › / esc | moves between a question's tabs (the last is the review with "Submit answers") or cancels the prompt, as the arrow keys and Esc do at the desk | code |
| type, then send, on a desktop session waiting for an answer | refused with "waiting for an answer on the desktop": the paste and its Enter would land in the open dialog | code |
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

The inbox screen (everything the desktop sent: unit failures, backups, the
nightly update, claude-code updates, watch triggers, the tutor's nudges;
what used to arrive on Telegram):

| Tap | Does | Lands |
|---|---|---|
| a row | expands or collapses its whole text | inbox |
| "open <screen>" on a row | opens the screen the sender named (watch, teach) | that screen |
| "accept" (watch triggers) | accepts that event in watch and drops the row | inbox |
| "link" | opens the link in the browser | browser |
| "dismiss" | drops the row on the desktop too | inbox |
| "clear all", first tap | arms it for 4 s; it reads "tap again" | inbox |
| "clear all", second tap | drops every row | inbox |
| a notification | opens the inbox, or the screen it names; "accept" on a watch alert accepts it without opening the app | the app |

The voice screen (speech to text on the desktop's faster-whisper, English and
Portuguese, through the bridge; the retired stt-via-telegram bot):

| Tap | Does | Lands |
|---|---|---|
| "record" | records from the microphone; the button counts the time | voice |
| the button while recording | stops and sends the clip; "transcribing on the desktop" until the text comes back | voice |
| "a file" | picks an audio or video file and sends it | voice |
| share audio or video to mandragora from any app | opens the voice screen and sends it | voice |
| "as said" / "to english" | keep the spoken language, or translate to English | voice |
| "auto" / a language | detect the language, or fix it | voice |
| "warm up" (only while the model is cold) | loads the model on the desktop | voice |
| "copy" / "share" / "forget" on a result | copies the text, shares it, or drops it from the phone's last 30 | voice |

The ask screen (the local model with the desktop's shell, the retired
llm-via-telegram bot; replies render as markdown):

| Tap | Does | Lands |
|---|---|---|
| type, send | plain text goes to the model; a slash command runs on the desktop: `/p <persona> <q>`, `/reg prompt, cmd, list or del`, `/run <name>`, `/sh <command>`, `/term <command>` (a terminal on the desktop), `/open <url>`, `/vj stats` or `undo`, `/context`, `/clear`, `/think`, `/help` | ask |
| stop (while it works and the box is empty) | stops between tool turns | ask |
| "thinking on" / "thinking off" | the model reasons before answering, the trace folded above each reply | ask |
| "clear" | forgets the conversation history the model sees | ask |
| a registered command's chip | runs it, as `/run <name>` | ask |
| "thought · tap to read" | unfolds the reasoning | ask |
| a shell or error line | unfolds its whole output | ask |

The teach screen (the Socratic tutor, the retired Telegram tutor; answers
render as markdown):

| Tap | Does | Lands |
|---|---|---|
| type, send | answers the tutor or asks it something; queued while claude is unavailable and sent when it comes back | teach |
| "warm up" / "long session" / "show the answer" / "done for today" | the tutor's /warmup, /long, /answer and /done | teach |
| "progress" | shows the streak, the due concepts, mastery and accuracy, the queue and the nudge switch | teach |
| "explain it back" on a due concept | asks you to teach that concept back | teach |
| "retry now" (only with a queue) | sends the queued messages now | teach |
| nudge switch | the tutor's idle nudges to the inbox, on or off | teach |

The watch screen (watch.mvr.ac, the retired watch bot's commands; triggers
also arrive in the inbox):

| Tap | Does | Lands |
|---|---|---|
| a watcher | expands it: its condition, last error, actions and what fired | watch |
| "accept" on a trigger | accepts that event | watch |
| "accept all" | accepts every open trigger of the watcher | watch |
| "pause" / "resume" | stops or restarts its polling | watch |
| "poll now" | polls it at once | watch |
| "delete", first tap | arms it; it reads "tap again" | watch |
| "delete", second tap | deletes the watch and every place it watches | watch |
| a trigger's title | opens its link | browser |
| the box at the bottom, send | builds a new watch from a sentence, as the bot's quick compose did | watch |

Lock screen and notification: prev / play / next act on the owner; the body
opens the app on the music screen; volume keys follow the pill (desktop side moves the desktop's
volume, phone side the phone's); the subtitle reads "artist · on the
desktop" or "artist · on the phone". No move button on the lock screen.

The lock screen shows whatever plays. Music and a desktop video (a
browser's YouTube tab, mpv) take turns: when only the video plays, that one
player becomes the video's, with its title, thumbnail and position and
"channel · YouTube on the desktop" under it; prev / play / next / seek act on
that tab and the volume keys on the desktop's volume. It stays there paused,
so the video can be resumed, until music plays again or the tab goes away.
Starting either one from the phone pauses the other. When both play anyway,
because one was started at the desk, a second media notification shows the
video beside the music. The app asks the desk every 5 s while a desktop
player exists, every 15 s otherwise and again the moment the screen turns
on, from the music player's own foreground service. The only other thing that
runs in the background is the inbox listener (settings, "listen in the
background"): a second foreground service with a quiet notification of its
own, started again after a reboot or an update, that holds one long poll to
the bridge and turns new items into notifications. Alerts reach the phone
only over the tailnet; while it is off they queue on the desktop and land on
reconnect.

Not now: ytdl client, sync status, a share target for anything but audio and video, deleting or forking sessions from the phone (the bridge already answers those). They get a card and a table
here when they come.

## Trying the app on the desktop

`phone-emu` runs the real APK in the Android emulator so the app can be
used, not looked at: tap, go back, lock the virtual phone, press its volume
keys. The first run creates a virtual device (Android 35, the phone's 1080×2400
screen) under `~/.local/share/mandragora-phone/`, boots it, builds the debug
APK unless `PHONE_APK` names one, installs it, grants notifications and music
access, pushes the song mpd is on plus the twelve newest files from `~/Music`
into the device's Music folder, at the same path below it as in `~/Music` so the phone side has something to play, and
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
palette's primary hue whenever it leaves the foreground. The app-level icon,
the one the lock screen shows beside the app's notifications and media
controls, is a grayscale variant that never changes. `app/icon/README.md`
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

## The quality gate

Nothing reaches the phone without passing `phone-gate`. `phone-push` runs it
on the APK it just built and publishes nothing when it fails; commits that
touch the app, either bridge or the gate itself run its fast half through
`mandragora-audit` check 22.

| check | what it holds | fast | full |
|---|---|---|---|
| detekt | Kotlin style and complexity, `quality/detekt.yml` on top of the defaults (Compose's dp literals, PascalCase composables and long composables excepted) | ✓ | ✓ |
| unit tests + Kover | the `logic` package (pure decisions: call folding, stopped turns, which player the lock screen shows, the either/or rule, the active-session test) has at least 80% line coverage; a decision belongs there, with a test, rather than in a composable or a service | ✓ | ✓ |
| ruff | bug rules only on both bridges: pyflakes, bugbear, async pitfalls, pylint errors | ✓ | ✓ |
| basedpyright | standard mode over both bridges and their tests (`pyrightconfig.json` at the repo root, so the editor reads it too) | ✓ | ✓ |
| pytest | `bridge/tests` and `.local/share/claude-bridge/tests`, against a fake `playerctl` and a fake `stt-core`, never the real ones; coverage may not fall under `quality/coverage-floors` | ✓ | ✓ |
| Android lint | warnings are errors | | ✓ |
| `phone-smoke` | a separate headless emulator (`mandragora-phone-check`, port 5560, never the one `phone-emu` gives you) installs the APK, launches it, locks, and requires the app still running, the music player and the inbox listener as its only foreground services, and no crash; then reboots it and requires no crash at boot | | ✓ |

What existed before the gate is grandfathered, not hidden: `quality/detekt-baseline.xml`,
`app/app/lint-baseline.xml` and `quality/pyright-baseline.json` list it, and only a new
finding fails. Fixing an old one and rewriting the baselines with `phone-gate
baseline` shrinks them; a diff that grows them is a decision to defend in the
commit. The coverage floors only go up: raise a floor when the tests raise the
number. `PHONE_GATE_MODE=fast phone-push` skips lint and the emulator, for when
the emulator itself is the broken thing; say so in the commit that follows.

## Traps

- Android stops background VPNs under battery pressure. Without *Always-on*
  and *Unrestricted*, the app is dead exactly when it is reached for. On this
  Samsung, One UI also puts apps it considers unused to sleep after a few
  days (Settings, Battery, Background usage limits); Tailscale and Sync-Fork
  belong in *Never sleeping apps*. The app tells the two failures apart: with
  no VPN up at all the header says "tailscale off" and the banner turns into
  "Tailscale is off on this phone · tap to turn it on", which asks Tailscale to
  connect and opens it; it reconnects to the desktop by itself the moment the
  VPN comes back.
- Sync-Fork's default trashcan versioning once held 17 GB on the phone.
  `phone-syncthing-bootstrap` posts folders with `versioning: ""`.
- The Sync-Fork GUI is localhost-only on the phone; the desktop reaches it
  through `adb forward tcp:18384 tcp:8384`, never over the network.
- `music.stignore` re-includes audio extensions and `*.lrc` only. A new file
  type for the phone needs a line there, or it never arrives.
- Wireless debugging's connect port is not the pairing port, and both change.
- The phone hotspot does not forward ICMP; failover scripts cannot ping it.
