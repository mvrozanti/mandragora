# mandragora-phone

An Android phone running as a Mandragora host: on the tailnet, a syncthing
peer, a KDE Connect pair, and the home of a native app that is the phone's
window into the desktop. It is not NixOS and never will be; the repo declares
what the phone is and ships what the desktop must serve for it, and the phone
side is a small set of apps installed once.

The device-level facts, the bootstrap recipe and the traps live in
[`../nix/hosts/mandragora-phone/README.md`](../nix/hosts/mandragora-phone/README.md);
the idea list is in [`BACKLOG.md`](../nix/hosts/mandragora-phone/BACKLOG.md).

## Intent

1. **Music plays in exactly one place.** The desktop holds a playback lease.
   The phone takes it over and resumes the same second locally; handing it
   back resumes mpd where the phone left off.
2. **The phone is a remote for the desk**, including the desktop's own sink
   volume, not only mpd's mixer.
3. **The phone is a node, not a client.** Its identity is declared in one
   place, the desktop reads it from there, and anything served for it is a
   tailnet service like any other.

## Layout

```
mandragora-desktop                                        phone
──────────────────                                        ─────
nix/hosts/mandragora-phone/identity.json ─▶ syncthing.nix
nix/snippets/tailnet.json                ─▶ networking.hosts "phone"
phone-bridge :6688 ◀── config · volume · lease · lyrics ── app
mpd :6600          ◀── mpd protocol over the tailnet ───── app
ytdl-web :6685     ◀── POST /api/download, GET /api/jobs ─ app (share target)
gpu-status :6684   ◀── /api/theme?colors=1 ─────────────── app (palette)
~/Music  ──syncthing send-only──────────────────────────▶  Music folder
~/Pictures/PhoneInbox/* ◀──syncthing send-receive──────── DCIM, WhatsApp, …
nix/hosts/mandragora-phone/app/ ──phone-push (adb over the tailnet)──▶ the app
```

Three surfaces, three owners:

| where | what | in the repo |
|---|---|---|
| **device** | Tailscale, Sync-Fork, KDE Connect, the app | `nix/hosts/mandragora-phone/` (README, identity, app) |
| **desktop** | `phone-bridge`, mpd on the tailnet, `phone-push`, inbox drain | `nix/modules/services/phone-bridge.nix`, `nix/modules/core/security.nix`, `nix/modules/desktop/phone-archiver.nix`, `.local/bin/` |
| **VPS** | nothing yet; the F-Droid repo is on the backlog | — |

## Workflow

- Change the bridge: edit `nix/hosts/mandragora-phone/bridge/server.py`,
  `mandragora-switch`. The unit restarts on content change.
- Change the app: edit `nix/hosts/mandragora-phone/app/`, commit, run
  `PHONE_ADB_ADDR=<ip:port> phone-push`. The dev shell is `nix develop
  /etc/nixos/mandragora#phone`.
- Nothing is pushed by hand. If it is on the phone and not in the repo, it is
  a bug, as for the kindle.
