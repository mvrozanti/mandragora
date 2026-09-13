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
- **Dashboard** — `kindle-dash` renders host status from VictoriaMetrics into a
  1272x1696 greyscale PNG on the desktop and pushes it; the device only draws.
- **Icons** — six in SimpleUI's idiom (48x48, `fill:none`, stroke 2, round caps):
  portrait, status, sync, dash, mpd, weather. Verified through KOReader's own
  lunasvg rasteriser, not just a desktop renderer, because two of them use
  constructs the house set never does (a rotated `<ellipse>`, elliptical arcs).
- **MPD** — now-playing and transport as a KOReader widget. Reaches the desktop
  over the **LAN** (`192.168.0.27:6600`), not the tailnet, for the reason in the
  README: userspace-networking gives ordinary sockets no tailnet route. Config in
  `/mnt/us/mandragora/mpd.conf`.

## In flight

- **Make the SimpleUI layout reproducible.** Right now it is a hand-restorable
  snapshot (`simpleui/sui_settings.reference.lua`), which breaks the "wipe the
  device and `kindle-push`" claim. Doing it properly means stopping KOReader,
  rewriting the generated `quick_actions_row_<hex>` instance ids to match
  whatever the target device created, and starting it again.

## Next up

- **`mandragora-sync.sh`** — the Sync tile still points at a script that does not
  exist. Should pull fresh art on-device so the desktop is not required. **Must go
  through the SOCKS/HTTP proxy** (`localhost:1055` / `:1056`) and target a tailnet
  address, not `kindle.mvr.ac` — see the networking section of the README.
- **Weather** — there is already an OpenWeatherMap key in sops
  (`weather/api_key`) and both `weather-menu.nix` and the waybar module consume
  it, so the data path exists. Render server-side like the dashboard: a day/week
  forecast as a big legible greyscale panel, pushed hourly. Same tier, same
  pipeline, near-zero battery. Reuse the existing key rather than adding another.
- **Desk-frame mode** — art that survives without a tap: either a SimpleUI Custom
  Screen with no modules and wallpaper at full opacity, or KOReader's screensaver
  pointed at `art/`. The screensaver route is the true zero-power frame, since
  e-ink holds the image while the device sleeps.

## Ideas

- **Drawing app** — the panel has a touchscreen (`/dev/input/event1: pt_mt`) and FBInk
  can draw. A sketchpad is the most natural native app for this device. Almost
  certainly tier 3 (armhf binary): stroke latency matters, and e-ink partial refresh
  (`--waveform DU` / A2) is the whole trick. Output could sync back as PNGs.
- **MPD visualiser** — now that the client exists, album art or a rendered
  spectrum as a full-screen panel. Server-rendered like the dashboard; the device
  draws one frame per track change, which is exactly the right refresh rate for
  e-ink.
- **A stable address for the desktop** — MPD is pinned to a DHCP lease
  (`192.168.0.27`). Either a reservation, or teach the widget to go through the
  SOCKS proxy so it can use the tailnet name instead.
- **Camera / video feed** — a still frame from a camera, refreshed on demand or on
  motion. Video is the one thing e-ink genuinely cannot do (a refresh is ~1 s), so the
  honest version is a *snapshot viewer*, not a stream. Pairs well with a webhook: push
  a frame to the device when something triggers.
- **Mandragora dashboards** — grafana/watch/fin summaries rendered **server-side** as a
  1236×1648 grayscale PNG and pushed to the device, rather than rendered on it. Reuses
  the whole `kindle-art` pipeline; the device only draws. Refresh every N minutes.
  Cheapest high-value app on this list.
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
