# `node-exporter/` — host metrics for mandragora-vps

Prometheus `node_exporter` running on `mandragora-vps`, scraped by the
desktop's VictoriaMetrics over tailnet. Backs the `Mandragora VPS`
Grafana dashboard (sibling to `Mandragora System` for the desktop).

## Container

| Container | Image | Port | Persistence |
|---|---|---|---|
| `node-exporter` | `quay.io/prometheus/node-exporter:v1.8.2` | `9100` (tailnet-bound) | none — `/proc`, `/sys`, `/` read-only bind from host |

## Network exposure

Bound to the tailnet IP only (`100.84.78.83:9100`), never `0.0.0.0`. No
Caddy vhost, no Authelia. Same posture as Loki: authentication is
"you must be on the tailnet."

## Scraping

Desktop VictoriaMetrics (`nix/modules/core/monitoring.nix`) scrapes
`100.84.78.83:9100` with `instance="mandragora-vps"`. The desktop's own
`node_exporter` keeps `instance="mandragora-desktop"`. Dashboards filter
by the `instance` label.

## Live location

`/home/opc/node-exporter/` on the VPS.

```
cd /home/opc/node-exporter && sudo docker compose up -d
```

## Env

`.env` (root-owned, gitignored) — all values optional:
- `TAILNET_VPS_IP` (default `100.84.78.83`)
- `NODE_EXPORTER_IMAGE` (default `quay.io/prometheus/node-exporter:v1.8.2`)

## Verification

From the desktop:

```
curl -s http://100.84.78.83:9100/metrics | head -5    # → metric lines
```

From off-tailnet (should fail):

```
curl -sI --connect-timeout 3 http://146.235.51.189:9100/metrics  # → timeout
```
