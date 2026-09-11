# `kindle` stack — `kindle.mvr.ac`

Drag-and-drop send-to-kindle. Upload a PDF, EPUB, DOC, TXT, or image;
the app emails it to the device's `@kindle.com` address and Amazon syncs
it over Whispernet. One FastAPI file + one static page.

## Surfaces

| Path | Auth | Purpose |
|---|---|---|
| `GET /` | Authelia | upload UI |
| `POST /api/send` | Authelia | multipart upload → SMTP relay to `@kindle.com` |
| `GET /healthz` | Authelia | liveness + `configured` flag |

Caddy routing is the standard gated-app pattern (forward-auth → reverse
proxy), same as `food`/`webhook`.

## Configuration

All values come from the colocated `.env` (never committed — see
`compose/README.md#secret-handling`). Template in `.env.example`:

| Var | Purpose |
|---|---|
| `KINDLE_EMAIL` | the device's `…@kindle.com` address (Amazon → Devices → Send-to-Kindle) |
| `SMTP_HOST` / `SMTP_PORT` / `SMTP_SECURITY` | outbound relay (`starttls` \| `ssl` \| `none`) |
| `SMTP_USER` / `SMTP_PASS` | relay credentials |
| `FROM_ADDR` / `FROM_NAME` | envelope `From` — must be on the Amazon approved-senders list |
| `MAX_UPLOAD_MB` | per-file cap (default 25, under most relay limits) |

Files are held in memory only and streamed straight to SMTP — nothing is
written to disk and no history is retained.

## Why email-to-kindle

Amazon exposes no public upload API; the `@kindle.com` mailbox is the
only scriptable path into the device. The sender must be pre-approved in
Amazon's Personal Document Settings, and the attachment must stay under
the relay's size limit, hence the per-file cap.

## Bringing it up

```
docker compose up -d --build
```

First run without a populated `.env` still serves the UI; `/api/send`
returns `503 not configured` until the relay values are set.
