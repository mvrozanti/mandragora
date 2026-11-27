# `share/` — file sharing, both ways (`share.mvr.ac`)

One stack for both directions of handing a file across:

- **them → me** — a friend opens `share.mvr.ac/` (public, no login), sends
  a file, and it lands in a gated inbox with a phone notification.
- **me → them** — the owner opens `/drop` (Authelia), uploads a file, and
  gets a public `share.mvr.ac/d/<token>` link to hand out.

`upload.mvr.ac` is retired with no redirect — it existed for minutes and
no one had the URL. This stack replaces the retired `gokapi` stack, which
did only the "me → them" half.

## Container

| Container | Image | Port | Persistence |
|---|---|---|---|
| `share` | `mandragora/share:local` (built from `./app`) | `8080` (in-container) | bind mount `./data` → `/data` |

Runs on the VPS in `seafile-net` (caddy reaches it by service name) plus
`tailnet-fwd`, which is how the `/api/theme` proxy reaches the desktop
palette at `host.docker.internal:6684` (the `socat-tailnet@6684` bridge).

## Surfaces

| Path | Auth | Purpose |
|---|---|---|
| `GET /` | none — public | the friend's send-to-me page |
| `POST /api/upload` | none — public | multipart file + optional `name`/`message`; stores it and notifies |
| `GET /d/<token>` | none — public | download a file the owner dropped |
| `GET /api/theme` | none — public | palette proxy for the page theme (`?colors=1`) |
| `GET /drop` | Authelia | the owner's drop-a-file page |
| `POST /api/drop` | Authelia | stores a drop and returns a public link |
| `GET /inbox` | Authelia | list of files people sent |
| `GET /inbox/api` | Authelia | that list as JSON |
| `GET /inbox/<id>/download` | Authelia | download one received file |

Caddy splits by path: `/inbox*`, `/drop*` and `/api/drop` are gated by
Authelia `two_factor`; everything else (the send page, the drop download
links, the theme proxy) is public. The app itself has no gate — caddy is
the gate.

## Storage

Two directories under `data/`, each holding one directory per item with a
`file` and a `meta.json`:

- `data/inbox/<id>/` — files people sent (them → me).
- `data/drops/<token>/` — files the owner shared (me → them).

Both `id` and `token` are `uuid4().hex` (32 hex chars); the download
routes reject anything that is not exactly that shape, so a key cannot
traverse out of its directory.

## Notification

After a them → me upload, the app posts to the desktop phone-bridge inbox
(`SHARE_INBOX_URL`, default `http://100.115.80.79:6688/api/inbox`) with
`source: share`, sender and filename as title, message as body, and a
`link` to `https://share.mvr.ac/inbox`. Best-effort: a missed notification
never fails the upload — the file is already on disk.

## Live location

`/home/opc/share/`

```
cd /home/opc/share && sudo docker compose up -d --build
```

## Env

`.env` (root-owned, gitignored) holds:
- `MVR_AC` (default: `mvr.ac`)
- optional `SHARE_IMAGE`, `SHARE_DATA_VOLUME`, `SHARE_INBOX_URL`,
  `SHARE_MAX_MB`, `SHARE_MAX_BODY`

## Verification

- `curl -sI https://share.mvr.ac/` → `200` (public, no auth).
- `curl -sI https://share.mvr.ac/inbox` → `302 → auth.mvr.ac/?rd=…`.
- `curl -F file=@./f -F name=ada https://share.mvr.ac/api/upload` →
  `{"ok": true, ...}` and a phone-inbox notification arrives.
