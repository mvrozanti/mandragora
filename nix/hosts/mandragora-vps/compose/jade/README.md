# `jade.mvr.ac` — self-hosted Jade QR PIN oracle

Public static page that replaces Blockstream's `blkstrm.com/pn`
(`jadefw.blockstream.com/pinqr/qrpin.html`) for a Blockstream Jade whose
blind-PIN oracle has been repointed at the [`pinserver`](../pinserver/)
stack. It runs the QR PIN round-trip in the visitor's phone browser:

1. scan the Jade's animated `UR:JADE-PIN` stream ("Step 1/2");
2. reassemble it into the CBOR `http_request` envelope and POST its
   `params.data` to the URL the device names (`/api/pin/set_pin` or
   `/api/pin/get_pin`);
3. wrap the oracle's reply as a `pin` RPC message, encode it as
   `UR:JADE-PIN` and animate it for the Jade to scan ("Scan Web QR 2/2").

## UI — "The lens"

Chosen in an `/elicit-ui` round of ten directions (artifact
`claude.ai/artifact/UugqBDX4dXPmHttTaTwX24`). The screen is one
rectangle used both ways: a full-bleed viewfinder while scanning, with a
segmented ring around the reticle (one arc per fragment), and then the
same rectangle turns white and becomes the reply QR, as large as the
screen allows, where the Jade is already pointing. That is what the
hardware needs: the Jade draws a 41-module QR at about 123 px and reads
with a QVGA camera.

It is a single-page state machine (`idle → scanning → relaying →
showing → done`, plus `error`), so a second unlock never needs a
reload. Details:

- The scan region passed to qr-scanner (`calculateScanRegion`) is the
  reticle's on-screen square mapped through `object-fit: cover` into
  video pixels, so qr-scanner's corner highlight sits inside the ring.
- In the reply state the frame indicator runs around the outside of the
  white box instead of the circle. The circle would cross the QR's
  corner finder patterns, which the Jade's reader needs unobstructed.
  This is the one deliberate deviation from the deck.
- Tap the QR to pause on a frame. The screen wake lock is held while the
  reply shows; a rejection is ignored.
- The flow chip reads `jade.mvr.ac` until the request decodes, then
  `Unlock` (`get_pin`) or `PIN setup` (`set_pin`). The URL suffix is only
  known after reassembly.
- The info button opens the details sheet (bottom on phones, docked
  right at ≥ 900 px): the raw status line with all twelve status strings,
  the relay (path, bytes, HTTP status, round-trip ms) and the decoded
  envelope.
- Page CSS consumes `--mv-*` tokens only. The literal `white` and `black`
  are functional: the QR's quiet zone and the scrim over the camera.

## Why a custom BC-UR module (`static/bcur.js`)

`@ngraveio/bc-ur` from the jsDelivr `+esm` CDN cannot decode in a browser:
jsDelivr bundles `bc-ur` and its `cbor-sync` dependency with **two separate
inlined `Buffer` polyfills**, so `cbor-sync`'s `instanceof Buffer` check
rejects every part with `Unsupported input format: undefined`. A global
`Buffer` polyfill does not help (each bundle binds its own copy).

`bcur.js` is a dependency-free implementation of exactly what the Jade
needs: minimal bytewords (table identical to the firmware's
`esp32_bc-ur/src/bytewords.cpp`), CRC-32, the 5-element fountain-part CBOR
`[seqNum, seqLen, messageLen, checksum, data]`, and reassembly from the
pure fragments. Fountain-mixed parts are ignored: the Jade loops its
animation, so every pure fragment is eventually scanned.

It was cross-validated against Blockstream's own C `bc-ur` (the firmware
library, compiled to WASM on the official page) for messages of 20–977
bytes at fragment sizes 50/8 and 60/10: firmware-encoded streams decode,
`bcur.js`-encoded streams are accepted by the firmware decoder, and pure
parts are byte-identical. The PIN reply mirrors the official page's
encoder parameters (max fragment 50, min 8).

## QR scanning

`static/qr-scanner.umd.min.js` and `static/qr-scanner-worker.min.js` are
`qr-scanner@1.4.1` (nimiq), byte-identical to the copy the official page
serves. The worker file is mandatory: browsers without a native
`BarcodeDetector` (Firefox, iOS Safari) decode through it, and without it
the camera preview works while no QR is ever recognized. The page forces
the worker path everywhere (`QrScanner._disableBarcodeDetector = true`).
The Jade emits fragments upper-cased (alphanumeric QR mode); the page
lower-cases before parsing.

## Static layout

| path | origin |
|---|---|
| `index.html`, `bcur.js` | this repo |
| `qr-scanner.umd.min.js`, `qr-scanner-worker.min.js` | vendored `qr-scanner@1.4.1` |
| `theme.css`, `theme.js`, `components.css` | canonical hub copy |

`cbor-x@1.6.6` (request decoding) and `qrcode@1.5.3` (reply rendering)
load from jsDelivr, pinned by version.

## Caddy

| match | upstream |
|---|---|
| `/api/theme*` | desktop theme bridge `host.docker.internal:6684`, rewritten to `/api/theme?colors=1` whatever the visitor asks, so the wallpaper path never leaves; `theme.js` falls back to its cache when the desktop sleeps |
| `/api/pin/*` | `pinserver:8096` (prefix stripped) |
| everything else | `jade:80` (nginx, this stack) |

`Permissions-Policy` allows `camera=(self)` — every other stack sets
`camera=()` — because the page needs the phone camera.

## Deploy

```sh
../../deploy-stacks.sh jade   # compose + static, then docker compose up -d
./deploy.sh                   # static only, no restart
```

Pointing a Jade at this oracle is a one-time USB step, not part of the
deploy: `set_jade_pinserver.py --set-url https://jade.mvr.ac/api/pin
--set-pubkey <server_public_key.pub>` from the Jade repo, confirmed on the
device. It is refused once the unit holds a PIN.
