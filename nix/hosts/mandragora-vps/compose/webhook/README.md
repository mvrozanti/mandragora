# `webhook` stack — `webhook.mvr.ac`

Public webhook receiver. POSTs (or any HTTP method) sent to
`https://webhook.mvr.ac/h/<slug>` are captured to a small SQLite store
and fan-out as Server-Sent Events for live consumers (the desktop
notifier is the first one).

## Surfaces

| Path | Auth | Purpose |
|---|---|---|
| `POST /h/<slug>` | none — public | webhook ingress; `<slug>` is the unguessable per-hook token (~16 chars of base64url) |
| `GET /` | Authelia | management UI (list/create hooks, browse events) |
| `GET /api/*` | Authelia | JSON management API |
| `GET /internal/events` | tailnet-only (`100.64.0.0/10`) | SSE stream of new events, consumed by the desktop notifier |

Caddy routing is encoded as labels in `docker-compose.yml` (note the
nested `handle` blocks under `/internal/*` for the tailnet gate).

## Storage

SQLite at `./data/webhook.db` (volume-mounted into the container at
`/data`). Per-hook retention is capped at
`WEBHOOK_MAX_EVENTS_PER_HOOK` (default 200) — oldest events are
pruned on each ingest. Bodies above `WEBHOOK_MAX_BODY` (default
1 MiB) are truncated at the boundary.

## Local desktop notifier

The desktop subscribes to `/internal/events` from its tailnet IP
(`webhook-notifier.service` in `nix/modules/user/services.nix`) and
fires a `notify-send` for every event. Click-actions on the
notification open `https://webhook.mvr.ac/?event=<id>`.

## Bringing it up

```
docker compose up -d --build
```

First boot creates the SQLite DB and writes the schema. Create hooks
via the UI — slugs are generated server-side. Public ingest URL is
displayed in the UI; copy-to-share.

## Why not webhook.site / adnanh/webhook?

We wanted a small data plane that the desktop can subscribe to live
(no polling), and a UI that fits in with the rest of the hub's retro
green theme. The whole thing is one Python file + one HTML file.
