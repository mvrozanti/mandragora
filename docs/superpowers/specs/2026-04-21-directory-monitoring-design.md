# Directory & System Monitoring — Design Spec

**Date:** 2026-04-21
**Status:** Approved

## Overview

Passive background collection of directory growth, network traffic, disk I/O, and system health metrics. Data is collected automatically and queryable on demand via a Grafana browser dashboard. No manual checking required; the data is there when you need it.

## Scope

- **Directories:** `/home/m` at depth 5, entries >= 100MB only
- **Network:** per-interface rx/tx byte rate
- **Disk I/O:** nvme0n1 read/write throughput
- **System:** CPU %, memory used, uptime, load average

## Service Architecture

```
systemd timer (every 6h, OnBootSec=5min, RandomizedDelaySec=30min)
        │
        ▼
du-exporter script
  - du --block-size=1 -d5 /home/m
  - filter entries < 100MB
  - write /var/lib/prometheus-node-exporter-textfiles/dirsize.prom
        │
        ▼
prometheus-node-exporter (:9100)
  - textfile collector reads dirsize.prom
  - also exposes built-in: CPU, RAM, network, disk I/O
        │
        ▼
prometheus
  - scrapes node_exporter every 5min
  - retains 90 days
        │
        ▼
grafana (:3000, localhost only)
  - datasource: prometheus (provisioned)
  - dashboard: "Mandragora System" (provisioned)
```

All services bind to `localhost` only. External access deferred to the Tailscale/Cloudflare stack.

## du-exporter Script

Language: Bash (no dependencies, trivially packaged in Nix).

Output format (Prometheus textfile):
```
# HELP dirsize_bytes Disk usage of directory in bytes
# TYPE dirsize_bytes gauge
dirsize_bytes{path="/home/m"} 187432960000
dirsize_bytes{path="/home/m/.cache"} 4231290880
dirsize_bytes{path="/home/m/Downloads"} 12884901888
```

Output file: `/var/lib/prometheus-node-exporter-textfiles/dirsize.prom`

On `du` failure: logs to journald, exits non-zero, previous `.prom` file is preserved so Prometheus sees last-known values rather than a gap.

## Grafana Dashboard: "Mandragora System"

**Row 1 — Directory Growth**
- Stacked area chart: top 15 dirs by current size, default range last 30 days
- Table: all tracked dirs with current size, size 7 days ago, delta, weekly growth rate (sortable)

**Row 2 — Network**
- Time series: rx/tx bytes/sec per interface, default last 24h
- Stat panels: total rx and tx transferred today

**Row 3 — Disk I/O**
- Time series: read/write throughput (MB/s) on nvme0n1, default last 24h

**Row 4 — System Health**
- Time series: CPU %, memory used %, default last 24h
- Stat panels: uptime, load average

Dashboard provisioned as JSON in Nix config — present on first boot, no manual UI setup.

## systemd Timer

```
OnCalendar=*-*-* 00,06,12,18:00:00
OnBootSec=5min
RandomizedDelaySec=30min
```

Runs as root to ensure full read access to `/home/m`.

## NixOS Module Structure

```
modules/core/monitoring.nix     ← service declarations
pkgs/du-exporter/default.nix    ← bash script as Nix derivation
```

`monitoring.nix` contains:
- `services.prometheus` (retention: 90 days, scrape interval: 5min)
- `services.prometheus.exporters.node` (textfile collector enabled)
- `services.grafana` (provisioned datasource + dashboard JSON)
- `systemd.services.du-exporter` + `systemd.timers.du-exporter`

Imported in the host config via `imports` in `hosts/mandragora-desktop/`.

## What Is Not In Scope

- Real-time alerting (future addition)
- Per-file tracking (only per-directory)
- External network exposure (deferred to Tailscale/Cloudflare work)
- Monitoring paths outside `/home/m`
