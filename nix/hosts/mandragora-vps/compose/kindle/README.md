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


## Device panel

Beyond the send-to-kindle relay, this stack is the control surface for
`mandragora-kindle` — the jailbroken Paperwhite 12 on the tailnet
(`100.80.53.92`). See `nix/hosts/mandragora-kindle/README.md` for the device side.

| surface | auth | does |
|---|---|---|
| `GET /` | Authelia | the panel — live screen, status, push, print, scriptlets |
| `GET /api/device` | Authelia | battery, firmware, uptime, free space, daemons, artwork count |
| `GET /api/screen.png` | Authelia | a PNG of the e-ink display right now |
| `POST /api/print` | Authelia | one line of text onto the panel via FBInk |
| `POST /api/push` | Authelia | file straight into `/mnt/us/documents` over the tailnet |
| `POST /api/send` | Authelia | the original Amazon email relay, unchanged |
| `GET /api/scriptlets`, `POST /api/scriptlets/{name}/run` | Authelia | list and run device scriptlets |
| `GET`/`POST /api/monitor` | Authelia | read or flip the monitoring switch |
| `GET /metrics` | **tailnet only** | Prometheus metrics for VictoriaMetrics |

### The screen mirror

FBInk on this device is a patched build: `--eval` segfaults and there is no
screenshot flag, so captures come from `/dev/fb0` directly. The framebuffer is
`1272x3392` at 8 bpp — **two pages of `1272x1696`**, and the whole page is
drawable (measured with `fbink -c -B BLACK`, which lights every pixel; the
1236x1648 in every spec sheet is the *11th* gen). One page is live and the other
reads uniform, so `_pick_live_page` chooses by counting distinct grey levels
rather than assuming an index.

The device gzips the frame (`dd | gzip -1`, ~470 KB, under a second) and the VPS
turns it into a PNG with Pillow, cached for `KINDLE_SCREEN_TTL` so a page reload
does not pull two megabytes again.

### Monitoring, and why it has a switch

`/metrics` is served **without Authelia but only to the tailnet** (`caddy.1_handle`
with a `not remote_ip 100.64.0.0/10` → 403 guard, the same shape `webhook` uses),
because Prometheus cannot complete an Authelia login. Everything else stays gated.
Exposing a raw container port would have published the whole app — push and
scriptlet-run included — to anyone on the tailnet, which is why it is a Caddy path
matcher instead.

Metrics: `kindle_up`, `kindle_battery_percent`, `kindle_charging`,
`kindle_storage_used_percent`, `kindle_art_images`, `kindle_uptime_seconds`,
`kindle_service_up{service=…}`, `kindle_scrape_duration_seconds`, and
`kindle_monitor_enabled`.

**The switch exists because scraping costs battery.** Every poll is an SSH round
trip to a device running off a cell that is meant to last weeks. So:

- the scrape interval is **5m**, not the 15–30s the other jobs use;
- the app caches the sample for `KINDLE_MONITOR_TTL` (4m) so a manual `curl` or a
  second scraper cannot multiply the real polling rate;
- and `POST /api/monitor {"enabled": false}` — the button on the panel — stops the
  SSH entirely. `/metrics` then serves only `kindle_monitor_enabled 0`, which keeps
  the series alive so the Grafana panel reads *paused* rather than going blank and
  looking like an outage.

The toggle persists in `/data/monitor`, so it survives a container restart.

### Grafana

`nix/modules/core/monitoring-grafana.nix` builds `dashboardKindle` alongside the
desktop and VPS dashboards, provisioned as `mandragora-kindle.json`. The scrape job
lives in `monitoring-metrics.nix` and the device's tailnet address is recorded in
`nix/snippets/tailnet.json` next to the other hosts.
