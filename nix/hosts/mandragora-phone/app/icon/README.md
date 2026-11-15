# The launcher icon

The icon is the two-tone sprout: three serrated leaves in mint-to-blue over a
stem that swells into a violet bulb and forks into two roots, on a deep navy
plate. It was chosen on 2026-11-15 from three rounds of candidates and it
follows the desktop's wallpaper palette.

## How it is built

`glyph.json` holds the two shapes (`leaf`, `body`) as SVG path data in the
108 dp adaptive-icon viewport, plus the five colours sampled from the chosen
render. The shapes were traced from the render with potrace after splitting
it into a leaf mask and a body mask by hue; the trace, not the bitmap, is what
ships, so the icon scales, themes and recolours like any vector.

`gen.py` writes the resources from `glyph.json`: twelve foreground vectors
(`drawable/ic_launcher_fg_<k>.xml`), twelve adaptive icons
(`mipmap-anydpi-v26/ic_launcher_<k>.xml`), twelve plate colours
(`values/ic_launcher_colors.xml`) and one monochrome layer
(`drawable/ic_launcher_mono.xml`, the two shapes in one tone, which Android 13
themed icons tint). Run it after editing `glyph.json`; its output is
committed so the gradle build needs no python. `gen.py --aliases` prints the
twelve `activity-alias` entries the manifest carries.

## Why twelve

Android never lets an app repaint its launcher icon at run time; the only
moving part is which of several aliases is enabled. Variant `k` is the chosen
look with every colour's hue rotated by `(k - 8) × 30°`, so variant 8 is the
render exactly and the others cover the hue circle. On every foreground the
app reads the desktop's live palette from the bridge, as it already does for
its own colours, and when the app leaves the foreground it enables the alias
whose bucket is nearest the palette's primary hue and disables the previous
one. The launcher repaints within seconds, no install needed. Some launchers
drop a home-screen shortcut when its component changes; the app drawer entry
always follows.

## The candidates, for next time

Three rounds were run on 2026-11-15, each published as a self-contained page
with the mock home screen, the Chess Lens mark as the benchmark and a ledger
per direction:

- `candidates-round2.html`: twelve drawn vectors in the Chess Lens grammar and
  sixteen renders (eight concepts, a depth prompt and a flat prompt each).
- `candidates-round3.html`: the shortlist, Root and halo, Planted and Cutout,
  seven more renders each with one thing varied, and a compare tray.

Round one, twelve plain vectors, was rejected on sight and is not kept.

Renders came from Flux.1-dev on the desktop GPU at 1024 px, 20 steps,
guidance 3.5, fixed seeds, one prompt per render; the prompts are in
`prompts/`, keyed by the ids the pages use. The full-size originals live
outside the repo at `~/.local/share/mandragora-phone/icon-renders/round{2,3}/`
on the desktop. To re-render or vary one, reuse the prompt with its seed, or
change the seed for a sibling of the same idea; the pages show every render
through the launcher mask, which is the only honest way to judge one.
