# mandragora-phone — backlog

The phone is a host without a package manager the repo controls. Everything
below has to arrive either as a file the desktop pushes, a service the desktop
serves over the tailnet, or an app the phone installs. The constraints at the
bottom are the ones that decide which.

## Shipped

- Host declaration: identity, tailnet entry, syncthing folders read from one
  place.
- `phone-bridge` on the desktop: config, desktop sink volume, the playback
  lease, lyrics.
- mpd reachable over the tailnet.
- `phone-push`: build the app in the `phone` dev shell and publish it to the
  bridge (2026-11-15; before that, install it over wireless debugging, still
  there behind `PHONE_ADB_ADDR`). The app offers the published build on home
  and hands it to Android's installer, so wireless debugging stays off.
- `phone-emu`: the same APK in the Android emulator on the desktop, against
  the real mpd and sink, with real songs in its Music folder.
- The app v0.1 (2026-11-02): Verbs home, The Stage player, six sheets, share
  target. Replaced on 2026-11-14 by the one-screen app built row by row from
  the tap map in the README: desktop volume, cover or lyrics, transport, the
  pill, "play something", a Media3 session whose remote player maps to mpd and
  routes the volume keys to the desktop sink, wallpaper palette. The ytdl,
  sync and hub clients left with it; git history before 2026-11-14 has them.

## In flight

- The live-cards build (2026-11-15) compiled and reviewed by reading, not
  yet tapped: run `phone-emu`, read the four tap-map tables top to bottom
  against `mpc status`, `wpctl get-volume` and `/api/lease`, then install on
  the device. Known to need the device: the handoff gap and position in both
  directions, ncmpcpp taking the pill back, the lock-screen skip buttons on
  the phone side, the money refresh path end to end, a service row opening
  the browser, airplane mode on each screen.

## Next up

Stated by the operator on 2026-11-15, in their order:

- A proper Claude and DeepSeek bridge: start a new session (the way
  `claude.mvr.ac` spawns tmux+claude today) or resume an existing one, for
  both models, from a card on home; the transcript rendered the way `salcc`
  renders it on the desktop (meaning-coloured: actions, risks, commands,
  hedges), not as raw terminal text.
- Notifications both ways: desktop notifications mirrored to the phone and
  the phone's to the desktop, each direction and each app class
  configurable. This is the first feature that needs a settings screen in
  the app; until then the app has no settings by design.
- ytdl ported in: the `ytdl-web` client that left with the one-screen
  rewrite returns as a card (paste or share a URL, watch the job, play the
  result on either side).
- More, to be picked from, suggested by the agent on the same day:
  "open on the desktop" as a share target (a URL goes to the desktop's
  browser or mpv, text to the clipboard); a glance card for the desktop
  itself (focused window, workspace, uptime, what is building) with
  lock / suspend / wake-on-lan under it; a home-screen widget and a Quick
  Settings tile for the music card ("move music here", play/pause); money
  alerts when the total moves more than a chosen share in a day; tap and
  hold on a hub row for the service's last log lines through the bridge;
  the local model (llm-via-telegram) reachable from a card without Telegram.

- Release keystore in sops (`phone/keystore`, `phone/keystore-password`),
  exported to the dev shell as `PHONE_KEYSTORE`/`PHONE_KEYSTORE_PASS`; then a
  minified release build (the debug APK is about 68 MB).
- The next desktop controls (ytdl, sync status) come back as a card on home
  and a table in the tap map.
- A fourth lock-screen button that moves the music, if the operator strikes
  the "no move button" line.
- Off the tailnet, "play something" could list the phone's own synced files
  instead of saying the desktop is unreachable.
- nix-on-droid (`nixOnDroidConfigurations.phone`): zsh, tmux, git, mpc from
  the same flake; reuse dotfiles through `home.file` + `readFile` only.
- F-Droid repo on the hub: `compose/fdroid/`, tailnet-only vhost (403 off the
  tailnet, no Authelia since the client cannot SSO), repo signing key in sops,
  tile under infra.
- The phone reports its own state to the bridge (battery, media volume, sync
  lag) so the hub can show a phone row.
- The lyrics cache under `~/Music/.lyrics` has no owner in the repo; decide
  whether the bridge's lrclib path should also fill it.

## Known, and deliberately not fixed

- mpd has no password on the tailnet. Every tailnet node is the operator's;
  the firewall is the gate, as for ytdl-web and cc-pocket.

## Ideas

- Share target for images → meme pipeline through the Phone Downloads folder.
- KDE Connect's run-command plugin as a fallback remote when the app is not
  installed.

## Constraints worth re-reading before starting any of these

- Android kills background VPNs: Tailscale needs always-on VPN and battery
  Unrestricted, or nothing here works when it is needed.
- Left and right screen edges are the system back gesture; never put a
  swipe there.
- Everything the app talks to is a tailnet ip from `/api/config`. Nothing
  resolves `*.mvr.ac`; when the tailnet is down the app fails closed.
- Exactly one device plays at a time. The lease on the desktop is the truth;
  the phone pushes its position while it owns playback.
