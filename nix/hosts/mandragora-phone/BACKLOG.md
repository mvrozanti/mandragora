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
- `phone-push`: build the app in the `phone` dev shell and install it over
  wireless debugging.
- The app v0.1 (2026-11-02): Verbs home, The Stage player, six sheets, share
  target. Replaced on 2026-11-14 by the one-screen app built row by row from
  the tap map in the README: desktop volume, cover or lyrics, transport, the
  pill, "play something", a Media3 session whose remote player maps to mpd and
  routes the volume keys to the desktop sink, wallpaper palette. The ytdl,
  sync and hub clients left with it; git history before 2026-11-14 has them.

## In flight

- Install the one-screen build and read the tap map top to bottom on the
  device, each row against `mpc status`.

## Next up

- Release keystore in sops (`phone/keystore`, `phone/keystore-password`),
  exported to the dev shell as `PHONE_KEYSTORE`/`PHONE_KEYSTORE_PASS`; then a
  minified release build (the debug APK is about 68 MB).
- The next desktop controls (ytdl, sync status, hub) come back as rows in the
  tap map under the "mandragora" title, which does nothing until then.
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
