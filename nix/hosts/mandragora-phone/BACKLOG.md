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

## In flight

- The app, phase 2: Verbs home, The Stage player, sheets, lock-screen session.

## Next up

- Verbs home: the operator said features are missing from the screen after
  seeing the deck. List them after the first install and add verbs.
- Round two of the deck: The Stage's hub sheet borrowing the live tiles from
  "The Hub, native".
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
- The Sync-Fork API key is entered once into the app and never leaves the
  phone; the desktop never stores it again.

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
