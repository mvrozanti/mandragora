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

## In flight

- **Mandragora dashboard** — host status rendered server-side as a 1272x1696
  greyscale PNG and pushed to the device. Reuses the whole `kindle-art` path; the
  device only draws.
- **MPD** — now-playing and transport as a KOReader widget talking to the
  desktop's MPD over the tailnet, with a `mpd.conf` for host/port/refresh.

## Next up

- **`mandragora-sync.sh`** — the Sync tile still points at a script that does not
  exist. Should pull fresh art (and later, other payloads) from `kindle.mvr.ac`
  on-device so the desktop is not required. Blocks the Sync tile being honest.
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
- **MPD interface** — `mpd.mvr.ac` already runs on the desktop. A now-playing screen
  plus transport controls is a near-perfect e-ink app: it repaints only on track
  change. Tier 2 (KOReader plugin talking to the MPD protocol over the tailnet) is
  probably enough, with a scriptlet fallback for play/pause.
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
