# `mandragora-kindle` — the Paperwhite as a host

A Kindle Paperwhite 12th gen (PW6, armhf, firmware 5.19.6), jailbroken with Véra
on 2026-09-12, running as a tailnet node. Everything the device needs beyond the
jailbreak itself lives in this directory and is shipped with `kindle-push`.

```
ssh root@100.80.53.92          # tailscale ssh, from anywhere
ssh -p 2223 root@<lan-ip>      # key-only dropbear, LAN fallback
```

## Layout on device

```
/mnt/us/mandragora/
├── bin/         tailscaled, tailscale (upstream armhf static), dropbear, dropbearkey
├── rc/          start.sh, install.sh, mandragora.conf, authorized_keys
├── scriptlets/  mandragora-*.sh — copied into /mnt/us/documents to become tiles
├── art/         e-ink-ready PNGs pushed by kindle-art
├── icons/       quick-action icons for the KOReader plugin
├── state/       tailscaled.state, dropbear host key, portrait.last
└── log/         start.log, dropbear.log, tailscaled.log
/mnt/us/koreader/plugins/mandragora.koplugin/    SimpleUI quick actions
/etc/upstart/mandragora.conf                      boot job (the one rootfs file)
```

## Boot persistence — the part that took the longest

The jailbreak's own `kmc.conf` runs `/mnt/us/emergency.sh` at `framework_ready`
and then `return 0`, **skipping every one of its own fixups** (gandalf setuid,
KMC permissions, chattr). It is an escape hatch, not a user hook. `RUNME.sh` is a
manual `;log runme` trigger, not boot. So there is no user boot hook and we ship
our own upstart job.

Two traps cost real time and are worth stating:

1. **`/mnt/us` is not mounted at `framework_ready`.** A `start.sh` that touches it
   immediately does nothing and logs nothing. `start.sh` waits up to 180 s for
   `bin/tailscaled` to appear before doing anything.
2. **Upstart kills a `pre-start` that blocks.** The wait above cannot happen inside
   the job, so `mandragora.conf` `setsid`s `start.sh` into the background and
   returns immediately. A `pre-start` that waits is a job that silently never ran.

`install.sh` writes the job the way the hotfix writes its own: `mntroot rw` → `cp`
→ `chmod 0664` → `chattr +i` → `mntroot ro`. Removing it is `chattr -i` then `rm`.

## Other device facts worth not rediscovering

- **root's home is `/tmp/root`**, not `/root`, and `/tmp` is wiped every boot — so
  `start.sh` recreates `~/.ssh/authorized_keys` on each start. Dropbear also refuses
  a home that is group-writable, and `/tmp/root` ships as `drwxrws---`; `start.sh`
  strips the group write bit.
- **The rootfs is read-only** outside `mntroot rw`.
- **MTP is unreliable for writes.** The FUSE mount cannot `mkdir`, `aft-mtp-cli` puts
  fail silently, and MTP is served by the stock UI so it vanishes when KOReader is
  foreground. Use SSH for everything.
- **Dropbear here has no `scp`/sftp-server.** Copy with `ssh host 'cat > path'`.
  KOReader's bundled dropbear does ship sftp, which is why `scp` works on 2222 only.
- **FBInk is at `/var/local/kmc/bin/fbink`**, version 1.25.0 with `Image=Yes`.
  `--eval` segfaults on this build; printing and `--image` are fine. Never rely on
  fbink for screenshots.
- **Screenshots come from `/dev/fb0`**: `virtual_size 1272,3392`, stride 1272, 8 bpp
  — two pages of `1272×1696`, visible area `1236×1648`, 8-bit grayscale. Page 0 is
  live and page 1 reads as uniform; pick the non-uniform page rather than assuming.
  `dd if=/dev/fb0 bs=1272 count=3392 | gzip -1` is ~470 KB and under a second.
- **Battery** is `/sys/class/power_supply/bd71827_bat/capacity`; AC is `bd71827_ac/online`.

## Scriptlets

Any `.sh` in `/mnt/us/documents` is indexed as a library item by the jailbreak's
`sh_integration`. The header controls how it appears:

```sh
#!/bin/sh
# Name: mandragora ▸ portrait
# Author: mandragora
# Icon: data:image/png;base64,…
```

- `mandragora-status.sh` — FBInk overlay: firmware, wlan, tailnet, battery, daemons.
- `mandragora-portrait.sh` — draws the next image from `art/` full-screen with
  `--dither --waveform GC16`, remembering position in `state/portrait.last`.

## KOReader plugin

`mandragora.koplugin` registers the scriptlets as **SimpleUI quick actions** through
SimpleUI's public `QA.register{ id, label, icon, execute }` API, so they appear as
tiles in the home screen's action row rather than only as items in the book list.
Plugin load order is not guaranteed, so it retries the lookup for ten seconds before
giving up.

## Energy

E-ink holds an image at zero power; only the refresh and the radio cost anything.
A portrait that changes hourly is close to free, a per-second clock is not. Design
everything here to **wake rarely, draw once, sleep**.

## Deploy

```sh
kindle-push          # rc, scriptlets, plugin, boot job, restart services
kindle-art 12        # 12 wallpapers from $WALLPAPER_DIR → e-ink → device
```

`kindle-push` takes the public key from `~/.ssh/id_ed25519.pub` at push time rather
than committing one. `kindle-art` shares the desktop's `$WALLPAPER_DIR`
(`~/Pictures/wllpps`), cover-cropping to `1236×1648`, converting to grayscale, and
Floyd–Steinberg dithering to 16 levels — the panel's actual depth.
