# mandragora-kindle — backlog

Ideas for the jailbroken Paperwhite, roughly ordered by how much new machinery each
needs. The device constraint that shapes all of them: **e-ink holds an image at zero
power, so cost is refreshes and radio, not CPU.** Anything that repaints continuously
is the wrong shape for this hardware; anything that draws once and sleeps is nearly
free. See the energy note in `README.md`.

Delivery is always one of three tiers — a scriptlet (`.sh` in `/mnt/us/documents`, no
daemon), a KOReader plugin (Lua, in-process, surfaced as a SimpleUI quick action via
`QA.register`), or a native armhf binary drawing through FBInk / registering an Awesome
window. Prefer the cheapest tier that works.

## Shipped

- **Portrait** — full-screen art, tap to shuffle, double-tap or swipe to exit.
  Started as an FBInk scriptlet and moved to a KOReader Lua widget, because a
  scriptlet draws once and exits: it cannot take a tap and KOReader repaints over
  it. Fed by `kindle-art` from the desktop's `$WALLPAPER_DIR` (823 images).
- **Status** — FBInk overlay: firmware, wlan, tailnet, battery, daemon state.
- **Monitoring** — `/metrics` scraped by VictoriaMetrics every 5m, Grafana
  dashboard `mandragora-kindle`, and a pause switch on the panel because every
  scrape is an SSH round trip to a battery device.
- **kindle.mvr.ac panel** — live e-ink mirror from `/dev/fb0`, direct push over
  the tailnet beside the Amazon email lane, print-to-screen, scriptlet runner.
- **Dashboard** — a KOReader widget that **pulls its own data**: one curl through
  the HTTP proxy fetches 25 series from VictoriaMetrics (~3.5 KB), re-fetched
  every 30 s, drawn as native widgets. No PNG, no push, no staleness. The older
  server-side Pillow renderer (`dash/render.py`) survives for pushed stills.
- **Icons** — six in SimpleUI's idiom (48x48, `fill:none`, stroke 2, round caps):
  portrait, status, sync, dash, mpd, weather. Verified through KOReader's own
  lunasvg rasteriser, not just a desktop renderer, because two of them use
  constructs the house set never does (a rotated `<ellipse>`, elliptical arcs).
- **Home-screen layout** — declared in `simpleui/layout.conf` and applied by
  `kindle-layout`, which patches only the `*_items` blocks with KOReader stopped
  and rolls back if the result does not parse. Row ids are discovered
  positionally, since SimpleUI regenerates its hashes per install.
- **MPD** — now-playing, transport, queue, scrubber, dithered cover art and a
  live spectrum analyser, as a KOReader widget that paints its own pixels
  rather than composing stock widgets. Reaches the desktop over the **LAN**
  (`192.168.0.27:6600`), not the tailnet, for the reason in the README:
  userspace-networking gives ordinary sockets no tailnet route. Config in
  `/mnt/us/mandragora/mpd.conf`.
- **MPD visualiser** — real audio, not faked motion. `mandragora-mpd-vis` on
  the desktop reads MPD's PCM fifo, does the FFT there, and streams 48 band
  magnitudes at 10 Hz over TCP 6612; the device redraws only the analyser's
  bounding box with an A2 waveform and promotes every fiftieth frame to a
  localised GC16 to clear the ghosting A2 leaves. The same connection serves
  album art pre-dithered to 16 levels. When the feed is down the meter goes
  flat and says so — it never animates from elapsed time.

- **SimpleUI layout is reproducible** — `simpleui/layout.conf` declares the rows;
  `kindle-layout.sh` applies them, discovering the generated
  `quick_actions_row_<hex>` instance ids off the device positionally so it
  survives a reinstall, and patching only the `*_items` blocks so hand-toggled
  settings are left alone.
- **Library and wallpaper sync** — automatic and event-driven. inotify on
  `~/Documents/library/books` and `~/Pictures/wllpps`, debounced, incremental by
  path+size manifest, with a 30-minute timer for whatever changed while the
  device was asleep. 247 books and 823 wallpapers on the device. The Sync tile is
  gone: there is nothing left to trigger by hand.
- **Lock screen shows a wallpaper instead of "Sleeping"** — this and desk-frame
  mode turned out to be the same feature arriving from two directions. Amazon's
  own sleep screen (`blanket`'s `screensaver` module, painting from
  `/usr/share/blanket/screensaver/`) never actually runs on this device: SimpleUI
  is itself a KOReader distribution, so KOReader is always the foreground app and
  owns suspend directly — `koreader.sh` runs its own
  `lipc-wait-event … com.lab126.powerd goingToScreenSaver …` and KOReader's
  `frontend/ui/screensaver.lua` paints the lock frame. Its shipped default is
  `screensaver_type = "disable"` with `screensaver_show_message = true`, which is
  the literal source of "Sleeping" (`Screensaver.default_screensaver_message`).
  `kindle-lockscreen` patches `settings.reader.lua` to `screensaver_type =
  "random_image"` pointed at `art/` with the message off, holding one of the 823
  e-ink images at zero power instead — the true zero-power frame the desk-frame
  idea wanted. KOReader caches settings in memory for its whole run, so applying
  this always stops and restarts KOReader; that restart is never automatic and
  is the one manual step after `kindle-push` (see README).

## In flight

- **MPD visualiser** — a server-side FFT reading MPD's PCM fifo and streaming
  band magnitudes to the device, with the widget repainting a bounding box on a
  fast waveform and a periodic GC16 to clear ghosting.
- **Status has the dashboard's old bug.** It still draws through
  `runScriptlet()` → `fbink`, so KOReader repaints over it exactly as it did to
  the dashboard. Wants the same treatment: a full-screen widget.

## Next up

- **Re-check `random_document`.** It reported "File not found" while the
  device held 124 unopenable files; those are gone now, so this may already be
  fixed. If it still fails, the cause is the other one below.
- **`random_document` opens nothing.** Reported as "File not found". Two
  candidate causes worth separating before fixing: the action may be picking
  from a stale history that still references moved files, or it may be picking
  any file in the tree — which, before the sync fix, meant a PNG or a
  stylesheet.

- **The Kindle's own status bar overdraws full-screen widgets.** The Amazon
  framework keeps a strip at the top (12-hour clock, battery) above whatever
  KOReader draws. Visible on the dashboard capture; a separate layer from the
  KOReader overpaint problem above.
- **Weather** — there is already an OpenWeatherMap key in sops
  (`weather/api_key`) and both `weather-menu.nix` and the waybar module consume
  it, so the data path exists. Render server-side like the dashboard: a day/week
  forecast as a big legible greyscale panel, pushed hourly. Same tier, same
  pipeline, near-zero battery. Reuse the existing key rather than adding another.

## Known, and deliberately not fixed

- **Scanned PDFs are not converted to epub, by design.** `A Headache in the
  Pelvis` read as gibberish in patches — `:H KDYH` for `We have`, a uniform +29
  character shift, with `¿`/`À` standing in for the `fi`/`fl` ligatures. The
  cause is not the converter: `pdffonts` reports `HiddenHorzOCR`, so the book is
  a **scan** whose only text is an Acrobat OCR layer floating over page images,
  and poppler extracts exactly the same garbage. Spaces are missing from those
  runs too, so decoding the shift only half-repairs it.

  Re-OCRing 582 pages would spend real CPU to produce a worse copy of something
  that already works, because the PDF *renders* perfectly — rendering uses the
  embedded glyphs and only extraction is broken. So the conversion script now
  skips PDFs carrying an OCR text layer, and the two affected epubs are retired
  to `~/Documents/library/.rejected/`. Read those two as PDFs.

  Two of 114 PDFs are scans. `Domain-Driven Design` also shows ~2.4% shifted
  paragraphs but is born-digital with subset fonts, so it is a different and
  much smaller problem, left alone.

## Ideas

- **Drawing app** — the panel has a touchscreen (`/dev/input/event1: pt_mt`) and FBInk
  can draw. A sketchpad is the most natural native app for this device. Almost
  certainly tier 3 (armhf binary): stroke latency matters, and e-ink partial refresh
  (`--waveform DU` / A2) is the whole trick. Output could sync back as PNGs.
- **A stable address for the desktop** — MPD is pinned to a DHCP lease
  (`192.168.0.27`). Either a reservation, or teach the widget to go through the
  SOCKS proxy so it can use the tailnet name instead.
- **Camera / video feed** — a still frame from a camera, refreshed on demand or on
  motion. Video is the one thing e-ink genuinely cannot do (a refresh is ~1 s), so the
  honest version is a *snapshot viewer*, not a stream. Pairs well with a webhook: push
  a frame to the device when something triggers.
- **More dashboards** — grafana/watch/fin summaries. Now that `dash.lua` proves the
  device can query VictoriaMetrics directly and draw native widgets, prefer that
  over the server-rendered PNG path for anything whose data lives in a queryable
  store.
- **Browser** — the stock WebKit browser already exists and is what Véra exploited.
  A launcher tile pointed at `hub.mvr.ac` is trivial; anything better means fighting
  a very old engine. Low effort, low ceiling.
- **Cellular automata (Lenia, rule 110)** — `lenia.mvr.ac` and `rule110.mvr.ac` already
  exist. On e-ink the interesting version is *not* animation but a single beautifully
  rendered generation, or a slow evolve-one-step-per-refresh mode that is closer to a
  meditation than a simulation. Same server-side render path as dashboards, or a native
  binary if stepping on-device is the point.

## Constraints worth re-reading before starting any of these

- No python on the device. Shell, Lua (inside KOReader), or a cross-compiled binary.
- Dropbear here has no `scp`; move files with `ssh host 'cat > path'`.
- `fbink --eval` segfaults on this build; `--image` and text printing are fine.
- Anything needing to survive reboot goes through `/mnt/us/mandragora/rc/start.sh`,
  never `emergency.sh`.
- The stock UI is Awesome WM; native windows must set a title like
  `L:A_N:application_PC:TS_ID:org.mandragora.foo` to be treated as first-class.
- Toolchain for tier 3: KindleModding `koxtoolchain` + `kindle-sdk` (Meson cross-file),
  target `kindlehf`.
