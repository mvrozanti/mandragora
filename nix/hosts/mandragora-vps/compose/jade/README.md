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

The decoded request is shown in the **audit** card.

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
| `theme.css`, `theme.js` | canonical hub copy |

`cbor-x@1.6.6` (request decoding) and `qrcode@1.5.3` (reply rendering)
load from jsDelivr, pinned by version.

## Caddy

| match | upstream |
|---|---|
| `/api/theme*` | desktop theme bridge `host.docker.internal:6684` (`?colors=1`, no wallpaper path) |
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
