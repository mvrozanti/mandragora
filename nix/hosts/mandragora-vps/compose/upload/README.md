# `upload/` — them-to-me file drop (`upload.mvr.ac`)

The reverse of `share.mvr.ac` (gokapi). `share` is me→them: drop a file,
get a public download link. `upload` is them→me: a friend sends a file
through a public page, it lands in a VPS directory, and a notification
hits the phone inbox so it is not missed.

## Container

| Container | Image | Port | Persistence |
|---|---|---|---|
| `upload` | `mandragora/upload:local` (built from `./app`) | `8080` (in-container) | bind mount `./data` → `/data` |

Runs on the VPS in `seafile-net` (caddy reaches it by service name) plus
`tailnet-fwd`, which is how the `/api/theme` proxy reaches the desktop
palette at `host.docker.internal:6684` (the `socat-tailnet@6684` bridge).

## Surfaces

| Path | Auth | Purpose |
|---|---|---|
| `GET /` | none — public | the friend's upload page |
| `POST /api/upload` | none — public | multipart file + optional `name`/`message`; stores it and notifies |
| `GET /api/theme` | none — public | palette proxy for the page theme (`?colors=1`) |
| `GET /files` | Authelia | the owner's inbox list |
| `GET /files/api` | Authelia | inbox list as JSON |
| `GET /files/<id>/download` | Authelia | download one upload |

The public surface is the upload page and its API only. Everything under
`/files` is gated by Authelia `two_factor`, so no one else can browse what
arrived — caddy is the gate, the app itself has none.

## Storage

Each upload is a directory under `data/uploads/<id>/` holding `file`
(the raw bytes) and `meta.json` (`id`, `ts`, `name`, `sender`, `message`,
`size`, `mime`). No shared index, so concurrent uploads cannot race. The
list endpoint reads the `meta.json` files newest-first. `id` is a
`uuid4().hex` (32 hex chars); the download route rejects anything that is
not exactly that shape, so the id cannot traverse out of the directory.

## Notification

After storing the file, the app posts to the desktop phone-bridge inbox
(`UPLOAD_INBOX_URL`, default `http://100.115.80.79:6688/api/inbox`) with
`source: upload`, the sender and filename as title, the message as body,
and a `link` to `https://upload.mvr.ac/files` so the notification opens
the (Authelia-gated) inbox. The notification is best-effort: a missed
notification never fails the upload — the file is already on disk.

## Live location

`/home/opc/upload/`

```
cd /home/opc/upload && sudo docker compose up -d --build
```

## Env

`.env` (root-owned, gitignored) holds:
- `MVR_AC` (default: `mvr.ac`)
- optional `UPLOAD_IMAGE`, `UPLOAD_DATA_VOLUME`, `UPLOAD_INBOX_URL`,
  `UPLOAD_MAX_MB`, `UPLOAD_MAX_BODY`

## Verification

- `curl -sI https://upload.mvr.ac/` → `200` (public, no auth).
- `curl -sI https://upload.mvr.ac/files` → `302 → auth.mvr.ac/?rd=…`.
- `curl -F file=@./f -F name=ada https://upload.mvr.ac/api/upload` →
  `{"ok": true, ...}` and a phone-inbox notification arrives.
