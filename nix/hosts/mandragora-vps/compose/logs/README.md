# `logs/` — custom Loki log viewer at log.mvr.ac

A single-file vanilla-JS log explorer that talks directly to Loki's
HTTP API. Replaces Grafana for the "show me logs" use case — Grafana
Explore was too heavy and the Drilldown app was still a Grafana panel.

## Containers

| Container | Image | Role |
|---|---|---|
| `logs-ui` | `nginx:1.27-alpine` | Serves `static/index.html`. Also carries the Caddy labels for `https://log.mvr.ac` — the UI on `/`, a Loki API proxy on `/api/loki/*`. |

## Caddy routing on `log.mvr.ac`

The single vhost serves two things via path matchers on the `logs-ui`
container:

| Path | Behavior |
|---|---|
| `/api/loki/*` | URI replace `/api/loki/` → `/loki/api/v1/`, reverse-proxy to `loki:3100` (same docker network). Carries the WebSocket upgrade for `/api/loki/tail`. |
| everything else | Reverse-proxy to nginx on port 80 inside the container, which serves the static UI. |

Both paths sit behind the same `forward_auth` against Authelia, so the
browser is authenticated once and same-origin XHR/WebSocket calls to
`/api/loki/*` carry the same session cookie.

## UI features

- Free-form LogQL input (default: `{host=~".+"}`).
- Label filter rows — one row per common label (`host`, `unit`,
  `container`, `compose_project`, `job`, `priority`). Click a chip
  to include, shift-click to exclude. Multi-select within a label
  builds a `=~"a|b|c"` matcher; multi-label combines with `,`.
- Time range selector (15m / 1h / 6h / 24h / 3d) and row-limit
  selector (500 / 2k / 5k / 20k).
- Volume histogram (canvas) showing `count_over_time` bucketed at
  ~1/60th of the selected range.
- Log list, newest first. Each row colour-coded by detected level
  (`ERROR/WARN/INFO/DEBUG`). Click a row to expand and see all
  stream labels.
- `tail` toggle: opens a WebSocket against `/api/loki/tail` and
  prepends new entries in real time. Caps the in-DOM list at 5k
  rows.

## Why not Grafana

- Standard Grafana Explore: too many panels, sidebars, settings — for
  what is fundamentally "tail with filters."
- Grafana Logs Drilldown app: better than Explore but still inside
  the Grafana frame.

The custom UI is ~400 LOC of vanilla HTML/CSS/JS, no build step, no
framework. Matches the `hub.mvr.ac` terminal theme so it lives in the
same visual language as the rest of the homelab.

## Live location

`/home/opc/logs/` on the VPS.

```
cd /home/opc/logs && sudo docker compose up -d
```

Joins `seafile-net` (declared `external: true`) — that's also where
`loki` lives, so the in-network reference `loki:3100` resolves.

## Editing the UI

The `static/` dir is a bind mount, so editing `index.html` and
copying it to `/home/opc/logs/static/index.html` on the VPS is enough
— no container restart needed for content changes (nginx serves the
mounted file directly).

## Env

`.env` (root-owned, gitignored). All optional:
- `MVR_AC` (default `mvr.ac`)
- `LOGS_UI_IMAGE` / `LOGS_UI_STATIC_VOLUME`

## Verification

From public (expect 302 → auth):
```
curl -sI https://log.mvr.ac/
```

From browser (after Authelia login):
- Page loads with terminal-themed UI
- Label chips populate (network tab shows `/api/loki/label/<name>/values`)
- Running a query hits `/api/loki/query_range`
- `tail` opens a WebSocket to `wss://log.mvr.ac/api/loki/tail?...`
