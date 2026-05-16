# `loki/` — central log aggregator

Loki + Promtail running on `mandragora-vps`. Logs from every service
across desktop + VPS land here. The UI lives at
[log.mvr.ac](https://log.mvr.ac) (reverse-proxied to the desktop's
existing Grafana, gated by Authelia).

## Containers

| Container | Image | Port | Persistence |
|---|---|---|---|
| `loki` | `grafana/loki:3.5.5` | `3100` (tailnet-bound) + `9095` grpc (internal) | bind `./data` → `/loki` |
| `loki-promtail` | `grafana/promtail:3.5.5` | — | docker socket scrape; positions in `/tmp` (ephemeral OK) |
| `loki-size-guard` | `alpine:3.20` | — | mounts `./data`, prunes oldest chunks if dir > 2 GB |

## Retention policy

**2 GB OR 3 days, whichever hits first.**

- 3-day cap: enforced inside Loki via `limits_config.retention_period: 72h`
  + the `compactor` with `retention_enabled: true`. Compactor sweeps
  hourly.
- 2 GB cap: enforced by the `size-guard` sidecar. Every 5 min it
  `du -sb /loki`; if over `CAP_BYTES` (env, default 2 GiB) it deletes
  the oldest 100 files under `/loki/chunks` via mtime. The compactor
  cleans up the resulting orphan indexes on its next pass.

The size guard is a safety net, not the primary bound — with
`crypto-fetcher` retired (see `../crypto-fetcher/RETIRED.md`) we
expect ~300–500 MB/day across all services, so the 3-day cap should
fire first under normal load.

## Network exposure

The Loki HTTP port (3100) is **bound to the tailnet IP only**
(`100.84.78.83:3100`) — not `0.0.0.0`. No Caddy vhost,
no Authelia. Authentication is "you must be on the tailnet."
This keeps the ingestion path cheap (no TLS, no auth round-trip)
and avoids the forward_auth UX issues that would come with
Promtail trying to push through a login portal.

The grpc port (9095) is not published; only the in-container
`loki-promtail` reaches it via the `seafile-net` docker network.

## What ships logs here

- **VPS docker stacks** — `loki-promtail` reads `/var/run/docker.sock`
  and tails every running container's stdout. Labels: `container`,
  `compose_project`, `stream` (stdout/stderr), `host=mandragora-vps`.
- **Desktop journald** — `services.promtail` on mandragora desktop
  pushes systemd-journal entries to `http://100.84.78.83:3100/loki/api/v1/push`
  over the tailnet. Labels: `unit`, `host=mandragora-desktop`,
  `job=systemd-journal`. Defined in `nix/modules/core/monitoring.nix`.

## Live location

`/home/opc/loki/` on the VPS.

```
cd /home/opc/loki && sudo docker compose up -d
```

## Env

`.env` (root-owned, gitignored) — all values optional, defaults in
the compose file:
- `TAILNET_VPS_IP` (default `100.84.78.83`)
- `LOKI_IMAGE` / `PROMTAIL_IMAGE` / `SIZE_GUARD_IMAGE`
- `LOKI_CAP_BYTES` (default 2 GiB)
- `LOKI_CHECK_INTERVAL` (default 300s)
- `LOKI_CONFIG_VOLUME` / `LOKI_DATA_VOLUME`

## Verification

From the desktop:

```
curl -sI http://100.84.78.83:3100/ready              # → 200 from tailnet
curl -s "http://100.84.78.83:3100/loki/api/v1/labels" | jq    # → label list
```

From off-tailnet (should fail — port not exposed publicly):

```
curl -sI --connect-timeout 3 http://<vps-public-ip>:3100/ready  # → timeout
```

UI:

```
curl -sI https://log.mvr.ac                          # → 302 → auth.mvr.ac/?rd=…
```

## Why no separate Grafana

The desktop already runs Grafana with VictoriaMetrics for metrics
(see `nix/modules/core/monitoring.nix`, reverse-proxied at
`grafana.mvr.ac`). Loki is added as a second provisioned datasource
on the same Grafana, and `log.mvr.ac` is a thin alternate vhost
pointing at the same backend. One UI, one auth gate, two datasources.
