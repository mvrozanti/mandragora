# `status/` — status.mvr.ac

Public, read-only view of the desktop and the VPS. Nothing a visitor sends
reaches the desktop: the page is static, and its data is pulled.

| Path | Served by | Source |
|---|---|---|
| `/` | `status` (nginx) | `static/` |
| `/data/status.json` | `status` (nginx) | written every 60 s by the desktop's `status-snapshot.timer`, served by gpu-status at `:6684/api/status-snapshot`, fetched by `status-puller` |
| `/data/theme.json` | `status` (nginx) | `:6684/api/theme?colors=1`, fetched by `status-puller` |
| `/data/pull.json` | `status` (nginx) | `status-puller`: last fetch success and failure times |
| `/api/status-probes` | `host-stats` (hub stack) | the VPS prober, with a 24 h ring in the `hub-state` volume |
| `/api/vps` | `host-stats` (hub stack) | live VPS cpu and disk |

When the desktop is down the page keeps the last snapshot, says how old it
is, and keeps the VPS card and the hosts row live from `host-stats`. When the
VPS is down the page is down; the desktop keeps recording, so the gap shows up
in the history afterwards.

The public series list, its thresholds and the forbidden metric families live
in `nix/modules/services/status-snapshot.nix`; the queries themselves in
`nix/modules/core/monitoring-exprs.nix`, shared with Grafana.

Deploy: `deploy-stacks.sh status`. `data/` is gitignored, so the sync never
deletes the live snapshot.
