# Directory & System Monitoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy a passive Grafana+Prometheus stack on Mandragora that tracks /home/m directory growth, network traffic, disk I/O, and system health — queryable via browser at http://localhost:3000.

**Architecture:** A custom `du-exporter` bash script runs every 6h via systemd timer, writing Prometheus textfile metrics for all directories under `/home/m` at depth 5 that are ≥100MB. `node_exporter` reads those files plus built-in OS metrics. Prometheus scrapes everything and retains 90 days. Grafana serves a provisioned "Mandragora System" dashboard — zero manual UI setup.

**Tech Stack:** NixOS `services.prometheus`, `services.prometheus.exporters.node`, `services.grafana`, `pkgs.writeShellApplication`, `systemd.timers`, `pkgs.writeTextDir`, `builtins.toJSON`.

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `pkgs/du-exporter/default.nix` | Bash script packaged as Nix derivation |
| Modify | `pkgs/overlays.nix` | Register du-exporter in the overlay |
| Create | `modules/core/monitoring.nix` | All service declarations: prometheus, node_exporter, grafana, systemd timer |
| Modify | `hosts/mandragora-desktop/default.nix` | Import monitoring.nix |

---

### Task 1: du-exporter package

**Files:**
- Create: `pkgs/du-exporter/default.nix`

- [ ] **Step 1: Write the package derivation**

Create `/etc/nixos/mandragora/pkgs/du-exporter/default.nix`:

```nix
{ writeShellApplication, coreutils }:
writeShellApplication {
  name = "du-exporter";
  runtimeInputs = [ coreutils ];
  text = ''
    OUTDIR="/var/lib/prometheus-node-exporter-textfiles"
    TMPFILE=$(mktemp "$OUTDIR/.dirsize.prom.XXXXXX")
    THRESHOLD=104857600

    printf '# HELP dirsize_bytes Disk usage of directory in bytes\n' > "$TMPFILE"
    printf '# TYPE dirsize_bytes gauge\n' >> "$TMPFILE"

    while IFS=$'\t' read -r size path; do
      if [ "$size" -ge "$THRESHOLD" ]; then
        printf 'dirsize_bytes{path="%s"} %s\n' "$path" "$size" >> "$TMPFILE"
      fi
    done < <(du --block-size=1 -d5 /home/m 2>/dev/null)

    mv "$TMPFILE" "$OUTDIR/dirsize.prom"
  '';
}
```

- [ ] **Step 2: Verify it evaluates cleanly**

```bash
cd /etc/nixos/mandragora
nix eval --impure --expr \
  'with import <nixpkgs> {}; callPackage ./pkgs/du-exporter/default.nix {}'
```

Expected: prints a store path like `/nix/store/...-du-exporter`

- [ ] **Step 3: Commit**

```bash
cd /etc/nixos/mandragora
git add pkgs/du-exporter/default.nix
git commit -m "feat(pkgs): add du-exporter textfile collector script"
```

---

### Task 2: Register du-exporter in the overlay

**Files:**
- Modify: `pkgs/overlays.nix`

- [ ] **Step 1: Add du-exporter to the overlay**

Edit `/etc/nixos/mandragora/pkgs/overlays.nix`. Replace the existing content with:

```nix
{ pkgs, ... }: {
  nixpkgs.overlays = [
    (final: prev: {
      claude-code = prev.callPackage ./claude-code/default.nix { };
      rtk = prev.callPackage ./rtk/default.nix { };
      du-exporter = prev.callPackage ./du-exporter/default.nix { };
    })
  ];
}
```

- [ ] **Step 2: Verify the flake evaluates**

```bash
cd /etc/nixos/mandragora
nix eval .#nixosConfigurations.mandragora-desktop.config.system.build.toplevel \
  --no-build 2>&1 | head -5
```

Expected: no errors — prints a store path or `«derivation ...»`

- [ ] **Step 3: Commit**

```bash
cd /etc/nixos/mandragora
git add pkgs/overlays.nix
git commit -m "feat(pkgs): register du-exporter in overlay"
```

---

### Task 3: Create monitoring.nix — prometheus, node_exporter, systemd timer

**Files:**
- Create: `modules/core/monitoring.nix`

- [ ] **Step 1: Write monitoring.nix**

Create `/etc/nixos/mandragora/modules/core/monitoring.nix`:

```nix
{ pkgs, ... }:

{
  services.prometheus = {
    enable = true;
    retentionTime = "90d";
    scrapeConfigs = [
      {
        job_name = "node";
        scrape_interval = "5m";
        static_configs = [ { targets = [ "localhost:9100" ]; } ];
      }
    ];
  };

  services.prometheus.exporters.node = {
    enable = true;
    enabledCollectors = [ "textfile" ];
    extraFlags = [
      "--collector.textfile.directory=/var/lib/prometheus-node-exporter-textfiles"
    ];
  };

  systemd.services.du-exporter = {
    description = "Directory size Prometheus textfile exporter";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = "${pkgs.du-exporter}/bin/du-exporter";
    };
  };

  systemd.timers.du-exporter = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 00,06,12,18:00:00";
      OnBootSec = "5min";
      RandomizedDelaySec = "30min";
      Persistent = true;
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/prometheus-node-exporter-textfiles 0755 root root - -"
  ];
}
```

- [ ] **Step 2: Verify it evaluates**

```bash
cd /etc/nixos/mandragora
nix eval .#nixosConfigurations.mandragora-desktop.config.system.build.toplevel \
  --no-build 2>&1 | head -5
```

Expected: no errors

- [ ] **Step 3: Commit**

```bash
cd /etc/nixos/mandragora
git add modules/core/monitoring.nix
git commit -m "feat(monitoring): add prometheus, node_exporter, and du-exporter timer"
```

---

### Task 4: Wire monitoring.nix into the host config

**Files:**
- Modify: `hosts/mandragora-desktop/default.nix`

- [ ] **Step 1: Add the import**

Edit `/etc/nixos/mandragora/hosts/mandragora-desktop/default.nix`. Add `../../modules/core/monitoring.nix` to the imports list, after `../../modules/core/ai-local.nix`:

```nix
imports = [
  ../../pkgs/overlays.nix
  ../../modules/core/globals.nix
  ../../modules/core/vm.nix
  ../../modules/core/storage.nix
  ../../modules/core/impermanence.nix
  ../../modules/core/boot.nix
  ../../modules/core/graphics.nix
  ../../modules/core/secrets.nix
  ../../modules/core/security.nix
  ../../modules/core/ai-local.nix
  ../../modules/core/monitoring.nix
  ../../modules/desktop/hyprland.nix
  ../../modules/desktop/kdeconnect.nix
  ../../modules/desktop/keyledsd.nix
  ../../modules/desktop/openrgb.nix
  ../../modules/desktop/seafile.nix
  ../../modules/desktop/steam.nix
  ../../modules/desktop/minecraft.nix
  ../../modules/user/home-manager.nix
  ../../modules/audits/default.nix
];
```

- [ ] **Step 2: Rebuild**

```bash
sudo nixos-rebuild switch --flake /etc/nixos/mandragora#mandragora-desktop
```

Expected: build completes, no activation errors

- [ ] **Step 3: Verify services are running**

```bash
systemctl status prometheus.service
systemctl status prometheus-node-exporter.service
systemctl status du-exporter.timer
```

Expected: prometheus and node-exporter are `active (running)`, timer is `active (waiting)`

- [ ] **Step 4: Run the exporter once manually to generate the first data file**

```bash
sudo systemctl start du-exporter.service
cat /var/lib/prometheus-node-exporter-textfiles/dirsize.prom | head -20
```

Expected: file exists, contains lines like `dirsize_bytes{path="/home/m/..."} 123456789`

- [ ] **Step 5: Verify prometheus is scraping node_exporter**

```bash
curl -s http://localhost:9090/api/v1/query?query=up | python3 -m json.tool
```

Expected: JSON response with `status: "success"` and a result showing `up{job="node"}` = 1

- [ ] **Step 6: Verify dirsize metrics are visible in prometheus**

```bash
curl -s 'http://localhost:9090/api/v1/query?query=dirsize_bytes' | python3 -m json.tool | head -30
```

Expected: JSON with multiple `dirsize_bytes` results with `path` labels

- [ ] **Step 7: Commit**

```bash
cd /etc/nixos/mandragora
git add hosts/mandragora-desktop/default.nix
git commit -m "feat(host): import monitoring module"
```

---

### Task 5: Add Grafana with provisioned dashboard

**Files:**
- Modify: `modules/core/monitoring.nix`

- [ ] **Step 1: Replace monitoring.nix with the full version including Grafana**

Overwrite `/etc/nixos/mandragora/modules/core/monitoring.nix` with:

```nix
{ pkgs, ... }:

let
  dashboard = {
    title = "Mandragora System";
    uid = "mandragora-system";
    schemaVersion = 38;
    version = 1;
    refresh = "5m";
    time = { from = "now-24h"; to = "now"; };
    panels = [

      # ── Row: Directory Growth ──────────────────────────────────────────────
      {
        id = 1; type = "row"; title = "Directory Growth"; collapsed = false;
        gridPos = { x = 0; y = 0; w = 24; h = 1; };
      }

      # Stacked area: top 15 dirs by current size
      {
        id = 2; type = "timeseries"; title = "Directory Sizes Over Time";
        gridPos = { x = 0; y = 1; w = 16; h = 9; };
        targets = [ {
          datasource = { type = "prometheus"; uid = "prometheus"; };
          expr = "topk(15, dirsize_bytes)";
          legendFormat = "{{path}}";
          refId = "A";
        } ];
        fieldConfig = {
          defaults = {
            unit = "bytes";
            custom = {
              fillOpacity = 20;
              gradientMode = "none";
              stacking = { mode = "normal"; group = "A"; };
            };
          };
          overrides = [ ];
        };
        options = {
          legend = { displayMode = "list"; placement = "bottom"; calcs = [ ]; };
          tooltip = { mode = "multi"; sort = "desc"; };
        };
      }

      # Table: all tracked dirs, sorted by size descending
      {
        id = 3; type = "table"; title = "Directory Sizes";
        gridPos = { x = 16; y = 1; w = 8; h = 9; };
        targets = [ {
          datasource = { type = "prometheus"; uid = "prometheus"; };
          expr = "sort_desc(dirsize_bytes)";
          instant = true;
          format = "table";
          refId = "A";
        } ];
        fieldConfig = {
          defaults = { unit = "bytes"; };
          overrides = [ ];
        };
        transformations = [
          {
            id = "organize";
            options = {
              excludeByName = { Time = true; "__name__" = true; instance = true; job = true; };
              renameByName = { path = "Directory"; Value = "Size"; };
            };
          }
        ];
        options = {
          sortBy = [ { desc = true; displayName = "Size"; } ];
          footer = { show = false; };
        };
      }

      # ── Row: Network ───────────────────────────────────────────────────────
      {
        id = 4; type = "row"; title = "Network"; collapsed = false;
        gridPos = { x = 0; y = 10; w = 24; h = 1; };
      }

      # Network rx/tx time series
      {
        id = 5; type = "timeseries"; title = "Network Traffic";
        gridPos = { x = 0; y = 11; w = 18; h = 8; };
        targets = [
          {
            datasource = { type = "prometheus"; uid = "prometheus"; };
            expr = ''rate(node_network_receive_bytes_total{device!~"lo|veth.*"}[5m])'';
            legendFormat = "rx {{device}}";
            refId = "A";
          }
          {
            datasource = { type = "prometheus"; uid = "prometheus"; };
            expr = ''rate(node_network_transmit_bytes_total{device!~"lo|veth.*"}[5m])'';
            legendFormat = "tx {{device}}";
            refId = "B";
          }
        ];
        fieldConfig = { defaults = { unit = "Bps"; }; overrides = [ ]; };
        options = {
          legend = { displayMode = "list"; placement = "bottom"; calcs = [ ]; };
          tooltip = { mode = "multi"; sort = "none"; };
        };
      }

      # RX today (stat)
      {
        id = 6; type = "stat"; title = "RX Today";
        gridPos = { x = 18; y = 11; w = 6; h = 4; };
        targets = [ {
          datasource = { type = "prometheus"; uid = "prometheus"; };
          expr = ''sum(increase(node_network_receive_bytes_total{device!~"lo|veth.*"}[24h]))'';
          refId = "A";
        } ];
        fieldConfig = { defaults = { unit = "bytes"; }; overrides = [ ]; };
        options = {
          reduceOptions = { calcs = [ "lastNotNull" ]; fields = ""; values = false; };
          colorMode = "value";
          graphMode = "none";
          justifyMode = "auto";
          textMode = "auto";
        };
      }

      # TX today (stat)
      {
        id = 7; type = "stat"; title = "TX Today";
        gridPos = { x = 18; y = 15; w = 6; h = 4; };
        targets = [ {
          datasource = { type = "prometheus"; uid = "prometheus"; };
          expr = ''sum(increase(node_network_transmit_bytes_total{device!~"lo|veth.*"}[24h]))'';
          refId = "A";
        } ];
        fieldConfig = { defaults = { unit = "bytes"; }; overrides = [ ]; };
        options = {
          reduceOptions = { calcs = [ "lastNotNull" ]; fields = ""; values = false; };
          colorMode = "value";
          graphMode = "none";
          justifyMode = "auto";
          textMode = "auto";
        };
      }

      # ── Row: Disk I/O ──────────────────────────────────────────────────────
      {
        id = 8; type = "row"; title = "Disk I/O"; collapsed = false;
        gridPos = { x = 0; y = 19; w = 24; h = 1; };
      }

      # Disk read/write throughput
      {
        id = 9; type = "timeseries"; title = "Disk I/O (nvme0n1)";
        gridPos = { x = 0; y = 20; w = 24; h = 8; };
        targets = [
          {
            datasource = { type = "prometheus"; uid = "prometheus"; };
            expr = ''rate(node_disk_read_bytes_total{device="nvme0n1"}[5m])'';
            legendFormat = "read";
            refId = "A";
          }
          {
            datasource = { type = "prometheus"; uid = "prometheus"; };
            expr = ''rate(node_disk_written_bytes_total{device="nvme0n1"}[5m])'';
            legendFormat = "write";
            refId = "B";
          }
        ];
        fieldConfig = { defaults = { unit = "Bps"; }; overrides = [ ]; };
        options = {
          legend = { displayMode = "list"; placement = "bottom"; calcs = [ ]; };
          tooltip = { mode = "multi"; sort = "none"; };
        };
      }

      # ── Row: System Health ─────────────────────────────────────────────────
      {
        id = 10; type = "row"; title = "System Health"; collapsed = false;
        gridPos = { x = 0; y = 28; w = 24; h = 1; };
      }

      # CPU + memory time series
      {
        id = 11; type = "timeseries"; title = "CPU & Memory";
        gridPos = { x = 0; y = 29; w = 18; h = 8; };
        targets = [
          {
            datasource = { type = "prometheus"; uid = "prometheus"; };
            expr = ''100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)'';
            legendFormat = "CPU %";
            refId = "A";
          }
          {
            datasource = { type = "prometheus"; uid = "prometheus"; };
            expr = "(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100";
            legendFormat = "Memory %";
            refId = "B";
          }
        ];
        fieldConfig = {
          defaults = { unit = "percent"; min = 0; max = 100; };
          overrides = [ ];
        };
        options = {
          legend = { displayMode = "list"; placement = "bottom"; calcs = [ ]; };
          tooltip = { mode = "multi"; sort = "none"; };
        };
      }

      # Uptime (stat)
      {
        id = 12; type = "stat"; title = "Uptime";
        gridPos = { x = 18; y = 29; w = 3; h = 4; };
        targets = [ {
          datasource = { type = "prometheus"; uid = "prometheus"; };
          expr = "time() - node_boot_time_seconds";
          refId = "A";
        } ];
        fieldConfig = { defaults = { unit = "s"; }; overrides = [ ]; };
        options = {
          reduceOptions = { calcs = [ "lastNotNull" ]; fields = ""; values = false; };
          colorMode = "none";
          graphMode = "none";
          justifyMode = "auto";
          textMode = "auto";
        };
      }

      # Load average 1m (stat)
      {
        id = 13; type = "stat"; title = "Load (1m)";
        gridPos = { x = 21; y = 29; w = 3; h = 4; };
        targets = [ {
          datasource = { type = "prometheus"; uid = "prometheus"; };
          expr = "node_load1";
          refId = "A";
        } ];
        fieldConfig = { defaults = { unit = "short"; }; overrides = [ ]; };
        options = {
          reduceOptions = { calcs = [ "lastNotNull" ]; fields = ""; values = false; };
          colorMode = "value";
          graphMode = "none";
          justifyMode = "auto";
          textMode = "auto";
        };
      }

    ];
  };

  dashboardDir = pkgs.writeTextDir "mandragora-system.json" (builtins.toJSON dashboard);
in

{
  services.prometheus = {
    enable = true;
    retentionTime = "90d";
    scrapeConfigs = [
      {
        job_name = "node";
        scrape_interval = "5m";
        static_configs = [ { targets = [ "localhost:9100" ]; } ];
      }
    ];
  };

  services.prometheus.exporters.node = {
    enable = true;
    enabledCollectors = [ "textfile" ];
    extraFlags = [
      "--collector.textfile.directory=/var/lib/prometheus-node-exporter-textfiles"
    ];
  };

  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "127.0.0.1";
        http_port = 3000;
      };
      analytics.reporting_enabled = false;
    };
    provision = {
      enable = true;
      datasources.settings = {
        apiVersion = 1;
        datasources = [ {
          name = "Prometheus";
          type = "prometheus";
          url = "http://localhost:9090";
          isDefault = true;
          uid = "prometheus";
        } ];
      };
      dashboards.settings = {
        apiVersion = 1;
        providers = [ {
          name = "mandragora";
          type = "file";
          disableDeletion = true;
          options.path = "${dashboardDir}";
        } ];
      };
    };
  };

  systemd.services.du-exporter = {
    description = "Directory size Prometheus textfile exporter";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = "${pkgs.du-exporter}/bin/du-exporter";
    };
  };

  systemd.timers.du-exporter = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 00,06,12,18:00:00";
      OnBootSec = "5min";
      RandomizedDelaySec = "30min";
      Persistent = true;
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/prometheus-node-exporter-textfiles 0755 root root - -"
  ];
}
```

- [ ] **Step 2: Verify the flake evaluates**

```bash
cd /etc/nixos/mandragora
nix eval .#nixosConfigurations.mandragora-desktop.config.system.build.toplevel \
  --no-build 2>&1 | head -5
```

Expected: no errors

- [ ] **Step 3: Rebuild**

```bash
sudo nixos-rebuild switch --flake /etc/nixos/mandragora#mandragora-desktop
```

Expected: build completes, Grafana service starts

- [ ] **Step 4: Verify Grafana is running**

```bash
systemctl status grafana.service
curl -s http://localhost:3000/api/health | python3 -m json.tool
```

Expected: service active, JSON `{"database": "ok", "version": "..."}`

- [ ] **Step 5: Verify the dashboard was provisioned**

```bash
curl -s http://admin:admin@localhost:3000/api/dashboards/uid/mandragora-system \
  | python3 -m json.tool | grep '"title"'
```

Expected: `"title": "Mandragora System"`

- [ ] **Step 6: Open the dashboard in a browser**

Navigate to http://localhost:3000 — default credentials are `admin` / `admin` (Grafana will prompt to change on first login). Go to Dashboards → Mandragora System. All four rows should be visible. The directory growth panels will show data as soon as Prometheus has scraped at least one du-exporter run (from Task 4, Step 4).

- [ ] **Step 7: Commit**

```bash
cd /etc/nixos/mandragora
git add modules/core/monitoring.nix
git commit -m "feat(monitoring): add grafana with provisioned Mandragora System dashboard"
```

---

### Task 6: Change Grafana admin password

The default `admin`/`admin` credential is fine for localhost-only access, but set a real password so it's ready when Tailscale/Cloudflare exposure is added later.

- [ ] **Step 1: Set a password via the Grafana CLI**

```bash
sudo -u grafana grafana-cli admin reset-admin-password <your-chosen-password>
```

Expected: `Admin password changed successfully`

- [ ] **Step 2: Verify login works**

```bash
curl -s http://admin:<your-chosen-password>@localhost:3000/api/org \
  | python3 -m json.tool | grep '"name"'
```

Expected: `"name": "Main Org."`
