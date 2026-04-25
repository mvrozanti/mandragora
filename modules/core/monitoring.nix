{ config, pkgs, ... }:

let
  dashboard = {
    title = "Mandragora System";
    uid = "mandragora-system";
    schemaVersion = 38;
    version = 1;
    refresh = "5m";
    time = { from = "now-24h"; to = "now"; };
    panels = [
      # ── Row: Directory Activity ──────────────────────────────────────────────
      {
        id = 1; type = "row"; title = "Directory Activity"; collapsed = false;
        gridPos = { x = 0; y = 0; w = 24; h = 1; };
      }
      {
        id = 2; type = "timeseries"; title = "Top 10 Size Changes (abs)";
        gridPos = { x = 0; y = 1; w = 12; h = 9; };
        targets = [ {
          datasource = { type = "prometheus"; uid = "prometheus"; };
          expr = "topk(10, abs(delta(dirsize_bytes[1h])))";
          legendFormat = "{{path}}";
          refId = "A";
        } ];
        fieldConfig = {
          defaults = {
            unit = "bytes";
            custom = { fillOpacity = 20; gradientMode = "none"; };
          };
        };
        options = {
          legend = { displayMode = "list"; placement = "bottom"; };
          tooltip = { mode = "multi"; sort = "desc"; };
        };
      }
      {
        id = 17; type = "timeseries"; title = "Top 10 File Count Changes (abs)";
        gridPos = { x = 12; y = 1; w = 12; h = 9; };
        targets = [ {
          datasource = { type = "prometheus"; uid = "prometheus"; };
          expr = "topk(10, abs(delta(dir_inode_count[1h])))";
          legendFormat = "{{path}}";
          refId = "A";
        } ];
        fieldConfig = {
          defaults = {
            unit = "short";
            custom = { fillOpacity = 20; gradientMode = "none"; };
          };
        };
        options = {
          legend = { displayMode = "list"; placement = "bottom"; };
          tooltip = { mode = "multi"; sort = "desc"; };
        };
      }

      # ── Row: GPU (NVIDIA) ───────────────────────────────────────────────────
      {
        id = 14; type = "row"; title = "GPU Performance"; collapsed = false;
        gridPos = { x = 0; y = 10; w = 24; h = 1; };
      }
      {
        id = 15; type = "timeseries"; title = "GPU Utilization";
        gridPos = { x = 0; y = 11; w = 18; h = 8; };
        targets = [
          {
            datasource = { type = "prometheus"; uid = "prometheus"; };
            expr = "nvidia_gpu_utilization";
            legendFormat = "GPU Core %";
            refId = "A";
          }
          {
            datasource = { type = "prometheus"; uid = "prometheus"; };
            expr = "nvidia_gpu_memory_utilization";
            legendFormat = "GPU Mem %";
            refId = "B";
          }
        ];
        fieldConfig = { defaults = { unit = "percent"; min = 0; max = 100; }; };
        options = { legend = { displayMode = "list"; placement = "bottom"; }; };
      }
      {
        id = 16; type = "stat"; title = "GPU Temp";
        gridPos = { x = 18; y = 11; w = 6; h = 8; };
        targets = [ {
          datasource = { type = "prometheus"; uid = "prometheus"; };
          expr = "nvidia_gpu_temperature_celsius";
          refId = "A";
        } ];
        fieldConfig = {
          defaults = {
            unit = "celsius";
            thresholds = {
              mode = "absolute";
              steps = [ { color = "green"; value = null; } { color = "orange"; value = 70; } { color = "red"; value = 85; } ];
            };
          };
        };
        options = { textMode = "value"; colorMode = "value"; graphMode = "area"; };
      }

      # ── Row: Network ───────────────────────────────────────────────────────
      {
        id = 4; type = "row"; title = "Network"; collapsed = false;
        gridPos = { x = 0; y = 19; w = 24; h = 1; };
      }
      {
        id = 5; type = "timeseries"; title = "Network Traffic (enp8s0)";
        gridPos = { x = 0; y = 20; w = 18; h = 8; };
        targets = [
          {
            datasource = { type = "prometheus"; uid = "prometheus"; };
            expr = ''rate(node_network_receive_bytes_total{device="enp8s0"}[5m])'';
            legendFormat = "rx";
            refId = "A";
          }
          {
            datasource = { type = "prometheus"; uid = "prometheus"; };
            expr = ''rate(node_network_transmit_bytes_total{device="enp8s0"}[5m])'';
            legendFormat = "tx";
            refId = "B";
          }
        ];
        fieldConfig = { defaults = { unit = "Bps"; }; };
        options = { legend = { displayMode = "list"; placement = "bottom"; }; };
      }
      {
        id = 6; type = "stat"; title = "RX Today";
        gridPos = { x = 18; y = 20; w = 3; h = 8; };
        targets = [ {
          datasource = { type = "prometheus"; uid = "prometheus"; };
          expr = ''sum(increase(node_network_receive_bytes_total{device="enp8s0"}[24h]))'';
          refId = "A";
        } ];
        fieldConfig = { defaults = { unit = "bytes"; }; };
      }
      {
        id = 7; type = "stat"; title = "TX Today";
        gridPos = { x = 21; y = 20; w = 3; h = 8; };
        targets = [ {
          datasource = { type = "prometheus"; uid = "prometheus"; };
          expr = ''sum(increase(node_network_transmit_bytes_total{device="enp8s0"}[24h]))'';
          refId = "A";
        } ];
        fieldConfig = { defaults = { unit = "bytes"; }; };
      }

      # ── Row: Disk I/O ──────────────────────────────────────────────────────
      {
        id = 8; type = "row"; title = "Disk I/O"; collapsed = false;
        gridPos = { x = 0; y = 28; w = 24; h = 1; };
      }
      {
        id = 9; type = "timeseries"; title = "Disk I/O (nvme0n1)";
        gridPos = { x = 0; y = 29; w = 24; h = 8; };
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
        fieldConfig = { defaults = { unit = "Bps"; }; };
      }

      # ── Row: System Health ─────────────────────────────────────────────────
      {
        id = 10; type = "row"; title = "System Health"; collapsed = false;
        gridPos = { x = 0; y = 37; w = 24; h = 1; };
      }
      {
        id = 11; type = "timeseries"; title = "CPU & Memory";
        gridPos = { x = 0; y = 38; w = 18; h = 8; };
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
        fieldConfig = { defaults = { unit = "percent"; min = 0; max = 100; }; };
      }
      {
        id = 12; type = "stat"; title = "Uptime";
        gridPos = { x = 18; y = 38; w = 3; h = 8; };
        targets = [ {
          datasource = { type = "prometheus"; uid = "prometheus"; };
          expr = "time() - node_boot_time_seconds";
          refId = "A";
        } ];
        fieldConfig = { defaults = { unit = "s"; }; };
      }
      {
        id = 13; type = "stat"; title = "Load (1m)";
        gridPos = { x = 21; y = 38; w = 3; h = 8; };
        targets = [ {
          datasource = { type = "prometheus"; uid = "prometheus"; };
          expr = "node_load1";
          refId = "A";
        } ];
        fieldConfig = { defaults = { unit = "short"; }; };
      }
    ];
  };

  dashboardDir = pkgs.writeTextDir "mandragora-system.json" (builtins.toJSON dashboard);
in

{
  services.prometheus = {
    enable = true;
    listenAddress = "0.0.0.0";
    port = 9090;
    retentionTime = "90d";
    scrapeConfigs = [
      {
        job_name = "node";
        scrape_interval = "15s";
        static_configs = [ { targets = [ "localhost:9100" ]; } ];
      }
      {
        job_name = "nvidia";
        scrape_interval = "1m";
        static_configs = [ { targets = [ "localhost:9835" ]; } ];
      }
    ];
  };

  services.prometheus.exporters.node = {
    enable = true;
    listenAddress = "0.0.0.0";
    enabledCollectors = [ "textfile" ];
    extraFlags = [
      "--collector.textfile.directory=/var/lib/prometheus-node-exporter-textfiles"
    ];
  };

  services.prometheus.exporters.nvidia-gpu = {
    enable = true;
    listenAddress = "0.0.0.0";
  };

  services.grafana = {
    enable = true;
    settings = {
      server = {
        protocol = "http";
        http_addr = "0.0.0.0";
        http_port = 3000;
      };
      analytics.reporting_enabled = false;
      security.secret_key = "SW2YcwTIb9zpOOhoPsMm";
      "auth.anonymous" = {
        enabled = true;
        org_name = "Main Org.";
        org_role = "Admin";
      };
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
    after = [ "systemd-tmpfiles-setup.service" ];
    requires = [ "systemd-tmpfiles-setup.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      UMask = "0022";
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
