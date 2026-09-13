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

- **Portrait** — cycles e-ink-converted art from `art/`, drawn with `--dither
  --waveform GC16`. Fed by `kindle-art` from the desktop's `$WALLPAPER_DIR`.
- **Status** — FBInk overlay: firmware, wlan, tailnet, battery, daemon state.

## Next up

- **`mandragora-sync.sh`** — the Sync tile currently points at a script that does not
  exist. Should pull fresh art (and later, other payloads) from `kindle.mvr.ac`
  on-device so the desktop is not required. Blocks the Sync tile being honest.
- **Desk-frame mode** — a SimpleUI Custom Screen with no modules and the wallpaper at
  full opacity, so art survives instead of being repainted by KOReader. Plus a timer
  that swaps the image hourly and sleeps.

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
