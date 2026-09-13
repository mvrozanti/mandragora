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

The Dash tile is a **KOReader widget that pulls its own data**. It queries
VictoriaMetrics directly over the tailnet and draws native widgets; nothing is
rendered on the desktop and nothing is pushed to the device.

- `koplugin/mandragora.koplugin/dash.lua` — a full-screen `InputContainer` whose
  child paints straight into the blitbuffer. One `curl` through the HTTP proxy
  (`localhost:1056`) fetches all 25 series in a single query — about 3.5 KB —
  parsed with KOReader's bundled `json`. Re-fetches every 30 s on a `UIManager`
  timer, `partial` refresh each tick and a `full` every eighth to clear
  accumulated ghosting. Tap re-fetches now; double-tap or a vertical swipe
  closes. When VictoriaMetrics is unreachable the footer reads
  `stale - <reason>` and the last good numbers stay on screen.

The single query is one selector with a `mountpoint=~"/|"` filter — the empty
alternative matters, because in PromQL an absent label matches the empty string,
so that one filter narrows the filesystem series to `/` while leaving every
non-filesystem metric untouched. Without it the same query returns 85 series of
mostly bind-mount noise instead of 25.

Two traps this went through, both worth not repeating:

- **Never draw with FBInk from inside a KOReader session.** The first version was
  a scriptlet that wrote `/dev/fb0` directly. KOReader does not know the screen
  changed, so its next repaint — a clock tick, a quote refresh, any partial
  update — stamps its widgets back on top of the image. Everything must go
  through KOReader widgets. `Status` still has this defect.
- **KOReader font sizes are not pixels.** `Font:getFace(name, size)` scales by
  screen DPI, so a "size 62" face is far larger than 62 px on this 300 dpi panel.
  Laying out from assumed pixel heights put every element on top of the next.
  Positions now come from measured `TextWidget:getSize()`, and the wordmark
  auto-shrinks until it fits its share of the width.

`dash/render.py` and `.local/bin/kindle-dash.sh` are the older server-side
renderer — a Pillow layout engine producing a `1272x1696` greyscale PNG, still
useful for a pushed still (a desk frame, a screensaver) but no longer what the
tile uses.

The `kindle_*` series come from the scrape job in `nix/modules/core/monitoring-metrics.nix`; see the panel README for how
`/metrics` is gated to the tailnet and why polling has a pause switch.

## Music — the MPD screen and its spectrum analyser

`mpd.lua` is the one widget here that does not compose KOReader widgets. It
subclasses `InputContainer` for gestures and lifecycle but implements
`paintTo` itself, drawing straight into the screen `BlitBuffer` with
`paintRect` / `hatchRect` / `RenderText`. That is deliberate: composing
`VerticalGroup`s gets you a KOReader dialog, and this screen wants the
dashboard's register — hairline rules, tracked small-caps labels, inverted
tags, meter bars — which needs pixel control. Layout is declared once in
`layout()` against the panel's real `1272×1696` grid and scaled from there,
and font sizes are requested in true pixels by dividing out
`Screen:scaleBySize`, so nothing depends on the emulator's DPI matching the
device's.

Type is `DroidSansMono` for every technical string (labels, numerals, chips,
tags) and `NotoSans-Bold` for the track title — both already on the device,
no font shipped. Ink is four values only: black, white, `0x60` for secondary
text and `0xAA` for tertiary, which is the same palette `dash/render.py`
uses and which survives the panel's 16 levels.

### Where the audio comes from

The Kindle is an MPD *client*, so it cannot read the server's fifo, and an
FFT on this CPU at 5 Hz is not free. The work happens on the desktop:

- `vis/server.py`, run as `mandragora-mpd-vis`
  (`nix/modules/services/mpd-vis.nix`), opens `/tmp/mpd.fifo` — the
  `audio_output { type "fifo" }` block already in `.config/mpd/mpd.conf` —
  non-blocking, takes 2048-frame Hann-windowed FFTs, folds the bins into 48
  log-spaced bands from 35 Hz to 16.5 kHz, applies a +5 dB/octave tilt so
  music's pink slope does not leave the top half of the panel dead, and
  normalises against a decaying AGC ceiling.
- The wire format is one line per frame: `F`, a state character, 48 bytes of
  bar height and 48 of peak height, each byte `value + 48`. 98 bytes at
  10 Hz is under a kilobyte a second, and the client decodes it with
  `line:byte(i) - 48` — no parsing.
- The state character is the honesty valve. `L` means PCM is actually
  flowing, `S` means the fifo is open but silent, `X` means it is not
  readable at all. The widget never fakes motion from elapsed time or
  bitrate: no feed means a flat meter, a boxed reason, and `NO FEED` in the
  corner.
- The same connection answers `COVER <size>`, which pulls the embedded
  picture out of MPD with `readpicture`/`albumart`, greyscales it, applies
  the same sigmoidal contrast and Floyd–Steinberg-to-16-levels treatment
  `kindle-art` uses, and returns a PNG the device only has to blit.

The helper listens on `6612` and the firewall opens it on `enp8s0` beside
MPD's own `6600`, because both are reached over the LAN for the reason in
the networking section below.

### Ghosting

A visualiser on e-ink lives or dies on this. Three rules:

1. **Only the visualiser's bounding box ever repaints.** The header, cover,
   metadata, queue and transport are painted once and left alone;
   `paintTo` dispatches on a zone so a frame redraws roughly a third of the
   screen's pixels, not all of them.
2. **Everything inside that box is pure black or pure white** — the bars,
   the peak caps, the dotted gridlines, the scrubber, the times. Nothing
   grey crosses the line, because the box refreshes with `a2`, a 2-level
   waveform that would dither anything in between into noise. The grey
   section labels sit deliberately just outside the box.
3. **Every `vis_gc16_frames` frames that box gets a `full` refresh
   instead** — one localised GC16 flash, ten seconds apart at the defaults,
   which clears the residue A2 leaves behind. Closing the widget or losing
   the feed forces one immediately so no ghost outlives the screen.

Bars are drawn as stacked segments rather than solid columns, which is both
the right idiom for a meter and a way to put roughly half as much ink on the
panel per frame.

### Touch

Whole-screen `paintTo` means whole-screen hit-testing: `paintAll` records
rectangles into `self.hits` as it draws, and `onTap` walks them. Transport
buttons invert on press with a `fast` refresh before the command goes out,
tapping the scrubber seeks, tapping a queue row plays it, tapping the
spectrum toggles the analyser off (and with it the polling and the radio),
and double-tap or a vertical swipe leaves — the same exit as `portrait` and
`dash`.

Configuration is `/mnt/us/mandragora/mpd.conf`; see `mpd.conf.example` for
every key and why each default is what it is.

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

### Why the MPD ports are opened on `enp8s0`, not `tailscale0`

Everything else the desktop serves is firewalled to `tailscale0`. MPD is the
deliberate exception, and it looks wrong on purpose:

```nix
networking.firewall.interfaces.enp8s0.allowedTCPPorts = [ 6600 ];
```

The Kindle talks to MPD with plain LuaSocket from inside KOReader, and by the
section above a plain socket on this device has no route to the tailnet. Only
the LAN address works, so the LAN interface is the one that has to be open.
Teaching the widget to speak through the SOCKS proxy is the fix that would let
this move to `tailscale0`; until then, moving it would close the port where the
device can reach it and open it where it cannot.

This has already been filed as a bug once by someone pattern-matching against
the other modules. It is not one.

## Getting out of things

The device has three ways back to the home screen, and which one applies depends
on where you are:

| where | way out |
|---|---|
| **open book** | **tap the top-left corner**, or long-press the **bottom-right corner** (the plugin's own zone), or tap the top → the **folder icon**, second from the right |
| **file browser** | **tap the top-left corner**, or the bottom bar's **Home** — the house, third of five |
| **portrait / mpd widget** | double-tap, or swipe up/down |

The bottom bar's first tab is labelled *Library* but its internal id is `home`,
and the one labelled *Home* is `homescreen` — SimpleUI's own naming, and the
easiest thing to misread when reading `sui_settings.lua`.

The top-left **tap** is bound in `gestures.lua` to SimpleUI's own
`simpleui_go_homescreen` action, in both reader and file-browser modes. It has
to be that action and not KOReader's `filemanager`: the latter fires the `Home`
event, which is a no-op when you are already in the file browser and can never
reach SimpleUI's home screen, since that is a different screen SimpleUI draws.
Beware that the corner sits inside `DSWIPE_ZONE_LEFT_EDGE`, the full-height
left-hand column — so a *tap* there goes home while a *swipe down* dims the
frontlight.

The bottom-right corner gesture is registered by `mandragora.koplugin` itself rather than
bound through KOReader's Gestures plugin, and it is **reader-only on purpose**.
SimpleUI puts a full-width `hold` zone on both its top bar and its nav bar
(`sui_topbar.lua`, `sui_bottombar.lua`) — a long-press anywhere on either opens
SimpleUI's settings — so a corner-hold in the file browser would fight it. In the
reader those bars do not exist, and the zone overrides `readerhighlight_hold` and
`readerfooter_hold`, which is exactly what KOReader's own corner gestures do.

## SimpleUI layout

The home-screen rows are declared in `simpleui/layout.conf` — one line per
quick-action row, ids separated by spaces — and applied with `kindle-layout`:

```
mandragora_portrait mandragora_dash mandragora_mpd mandragora_status
continue bookmark_browser random_document stats_calendar frontlight
```

`kindle-layout` stops KOReader first, because SimpleUI holds its settings in
memory and rewrites the file on exit, so an edit underneath a running KOReader is
silently clobbered. It patches **only** the `*_items` blocks, leaving every other
setting the device has accumulated alone, checks the result parses as Lua, and
restores its backup if it does not.

It discovers the row instance ids positionally rather than hard-coding them.
SimpleUI names rows with generated hashes (`quick_actions_row_248e20`) that differ
on every install, so the rows themselves must already exist — add them in
SimpleUI's settings first, then `kindle-layout` fills them. That is the one manual
step a fresh device still needs.

`simpleui/sui_settings.reference.lua` is a snapshot of the whole settings file
from 2026-09-12, kept as a record of what the working configuration looked like
rather than as something any script applies.

## Library and wallpaper sync

Books and wallpapers reach the device by themselves; there is no Sync tile and
nothing to run by hand.

- `.local/bin/kindle-sync.sh` — diffs a local manifest against the device by
  path and size and tars across only what is missing, so the library reconciles
  incrementally rather than re-pushing every time. Refuses to push if the device
  would drop below a free-space floor, and exits 0 quietly when the device is
  unreachable, which is its normal state.
- `.local/bin/kindle-sync-watch.sh` — an inotify loop over
  `~/Documents/library/books` and `~/Pictures/wllpps`, debounced so unpacking a
  folder of books is one sync and not forty. **Not** a `systemd.path` unit:
  those do not watch recursively, so every book in a subdirectory would be
  missed.
- `nix/modules/desktop/kindle-sync.nix` — the user service, plus a 30-minute
  timer that reconciles whatever changed while the device was asleep.

Wallpapers are delegated to `kindle-art`, which converts only what is missing.
Packaging it surfaced a latent bug worth remembering: its parallel convert
shells out to `bash`, which is **not on a systemd unit's PATH**, so conversion
died with exit 127. It had only ever worked because interactive shells have bash.

## Desktop commands, and where they are defined

`kindle-art` and `kindle-sync` are `writeShellApplication`s in
`nix/modules/desktop/kindle-sync.nix`, so their runtime dependencies
(imagemagick, openssh, inotify-tools) are closed over rather than borrowed from
whatever happens to be installed. `kindle-push`, `kindle-dash` and
`kindle-layout` are still plain `writeShellScriptBin`s in `home.nix` and rely on
the ambient environment.

Define each one **once**. `kindle-art` was briefly declared in both files; the
per-user profile shadows the system one, so the version actually on `PATH` was
the unwrapped one, working only because imagemagick happened to be installed
globally.

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
