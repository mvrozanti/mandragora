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
  — two pages of `1272×1696`, **all of which is drawable**, 8-bit grayscale. Page 0 is
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
- `mandragora-portrait.sh` — legacy tier-1 draw of the next image from `art/`.
  Superseded by the Portrait KOReader widget; kept for the stock-UI tile.
- `mandragora-dash.sh` — draws `dash/latest.png` full-screen. See Dashboard below.

## KOReader plugin

`mandragora.koplugin` registers the scriptlets as **SimpleUI quick actions** through
SimpleUI's public `QA.register{ id, label, icon, execute }` API, so they appear as
tiles in the home screen's action row rather than only as items in the book list.
Plugin load order is not guaranteed, so it retries the lookup for ten seconds before
giving up.

## Dashboard

`kindle-dash` renders a status dashboard **on the desktop** (no Python on the
device — see Constraints) and pushes it to the device as a plain PNG; the device
only draws it. Two pieces:

- `nix/hosts/mandragora-kindle/dash/render.py` — Pillow layout engine. Takes a
  JSON blob describing hosts/metrics/services on stdin (or `--data file`) and
  writes a `1272×1696` 8-bit grayscale PNG: `MANDRAGORA` wordmark + a live clock,
  one bordered panel per host (desktop / vps / kindle) with a status dot,
  an `ONLINE`/`OFFLINE` tag, and stat tiles (label, big value, optional
  sub-text and a thick progress bar), a tailnet-triangle glyph, and a footer.
  Pure black-on-white with one flat mid-gray for secondary text — no gradients,
  no anti-aliased hairlines (borders/bars are ≥3px, plain `ImageDraw` rectangles
  so edges stay crisp on the panel's 8bpp buffer). Font is Iosevka Nerd Font
  (already on the desktop), resolved at every run via `fc-match` rather than a
  baked-in `/nix/store` path, so it survives GC.
- `.local/bin/kindle-dash.sh` — queries VictoriaMetrics
  (`http://localhost:8428`) for `node_load1`, `node_memory_{MemAvailable,MemTotal}_bytes`,
  `node_filesystem_{avail,size}_bytes{mountpoint="/"}`, `nvidia_smi_utilization_gpu_ratio`,
  `nvidia_smi_temperature_gpu` (desktop + vps via their `instance` label), and
  `kindle_{battery_percent,charging,storage_used_percent,uptime_seconds,art_images,service_up}`
  plus `up{instance=...}` for the online/offline dot, formats them (human byte
  sizes, used-fraction bars, compact uptime), builds the JSON with `jq`, renders
  via `nix shell --impure … python3.withPackages (ps: [ps.pillow])`, and ships
  the PNG with `ssh root@kindle 'cat > /mnt/us/mandragora/dash/latest.png'`
  (no `scp` on this dropbear — see Constraints).
- `nix/hosts/mandragora-kindle/scriptlets/mandragora-dash.sh` — the on-device
  half: `fbink --image` of `dash/latest.png`, `--dither --waveform GC16`, same
  as `mandragora-portrait.sh`.

Run `kindle-dash` whenever the numbers should refresh (a cron/systemd timer is
the obvious next step, e.g. hourly — see the Energy note); the device tile just
redraws whatever is already on disk.

The `kindle_*` series come from the scrape job in `nix/modules/core/monitoring-metrics.nix`; see the panel README for how
`/metrics` is gated to the tailnet and why polling has a pause switch.

## The device has no tailnet route for ordinary sockets

`tailscaled` runs `--tun=userspace-networking`, which creates **no network
interface**: `ip route` has nothing for `100.64.0.0/10`. Only the `tailscale` CLI
can reach peers, through tailscaled's own IPC. Everything else — LuaSocket,
busybox `nc`, `ping`, `wget` — fails identically. Proof, from the device:

```
nc -w3 100.115.80.79 6600     → Connection timed out
ping 100.115.80.79            → 100% loss
tailscale ping 100.115.80.79  → 9ms, direct
tailscale nc  100.115.80.79 6600 → full MPD reply
```

This is why `start.sh` also passes `--socks5-server=localhost:1055` and
`--outbound-http-proxy-listen=localhost:1056`. With those, ordinary clients reach
the tailnet through a proxy:

```sh
http_proxy=http://localhost:1056 wget -O- http://100.84.78.83:9100/metrics   # works
ALL_PROXY=socks5://localhost:1055 <client>                                    # works
```

**Anything on-device that wants to reach the VPS or the desktop must go through
one of those two ports.** `mandragora-sync.sh` in the backlog is the obvious
case — "pull art from `kindle.mvr.ac`" cannot work as a plain fetch. Note that
`kindle.mvr.ac` resolves to the *public* IP from the device, which is not a
tailnet destination, so the proxy returns 502 for it; use the tailnet address.

Kernel TUN mode would remove the need for the proxies entirely and `/dev/net/tun`
does exist here, but userspace mode is what is known to work on this device and
the proxies are additive and free.

## SimpleUI layout

`simpleui/sui_settings.reference.lua` is a **snapshot, not a source of truth** —
a copy of the working configuration so a wiped device can be put back by hand
rather than rediscovered. The layout it captures:

```
row 1 — apps     portrait · mpd · dash · status · sync
row 2 — system   continue · bookmarks · brightness · night · wifi · power
```

Two things make this awkward to automate, and both are why `kindle-push` does
**not** ship it:

- SimpleUI holds its settings in memory and rewrites the file when KOReader
  exits, so any edit made underneath a running KOReader is silently clobbered.
  Writing it means stopping KOReader first.
- The quick-action rows are *instances* with generated ids
  (`quick_actions_row_248e20`), so the file is not portable between devices as-is
  — the ids would have to be rewritten to whatever a fresh install generated.

Restoring by hand: stop KOReader, copy the file to
`/mnt/us/koreader/settings/simpleui/sui_settings.lua`, start KOReader. Restoring
through the UI is Settings → Home Screen (add the Quick Actions Rows) and then
each row's Quick Actions entry to fill its slots.

## Energy

E-ink holds an image at zero power; only the refresh and the radio cost anything.
A portrait that changes hourly is close to free, a per-second clock is not. Design
everything here to **wake rarely, draw once, sleep**.

## Deploy

```sh
kindle-push          # rc, scriptlets, plugin, boot job, restart services
kindle-dash          # render host status → device
kindle-art 12        # 12 wallpapers from $WALLPAPER_DIR → e-ink → device
```

`kindle-push` takes the public key from `~/.ssh/id_ed25519.pub` at push time rather
than committing one. `kindle-art` shares the desktop's `$WALLPAPER_DIR`
(`~/Pictures/wllpps`), cover-cropping to `1272×1696`, converting to grayscale, and
Floyd–Steinberg dithering to 16 levels — the panel's actual depth.
