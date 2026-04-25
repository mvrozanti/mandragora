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
      {
        id = 1; type = "row"; title = "Directory Activity"; collapsed = false;
        gridPos = { x = 0; y = 0; w = 24; h = 1; };
      }
      {
        id = 2; type = "timeseries"; title = "Top 10 Directory Changes (abs)";
        gridPos = { x = 0; y = 1; w = 16; h = 9; };
        targets = [ {
          datasource = { type = "prometheus"; uid = "prometheus"; };
          expr = "topk(10, abs(delta(dirsize_bytes[24h])))";
          legendFormat = "{{path}}";
          refId = "A";
        } ];
        fieldConfig = {
          defaults = {
            unit = "bytes";
            custom = {
              fillOpacity = 20;
              gradientMode = "none";
            };
          };
        };
        options = {
          legend = { displayMode = "list"; placement = "bottom"; };
          tooltip = { mode = "multi"; sort = "desc"; };
        };
      }
      {
        id = 3; type = "table"; title = "Change Magnitude (24h)";
        gridPos = { x = 16; y = 1; w = 8; h = 9; };
        targets = [ {
          datasource = { type = "prometheus"; uid = "prometheus"; };
          expr = "sort_desc(topk(10, abs(delta(dirsize_bytes[24h]))))";
          instant = true;
          format = "table";
          refId = "A";
        } ];
        fieldConfig = { defaults = { unit = "bytes"; }; };
        transformations = [
          {
            id = "organize";
            options = {
              excludeByName = { Time = true; "__name__" = true; instance = true; job = true; };
              renameByName = { path = "Directory"; Value = "Change"; };
            };
          }
        ];
        options = {
          sortBy = [ { desc = true; displayName = "Change"; } ];
          footer = { show = false; };
        };
      }
      {
        id = 4; type = "row"; title = "Network"; collapsed = false;
        gridPos = { x = 0; y = 10; w = 24; h = 1; };
      }
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
        fieldConfig = { defaults = { unit = "Bps"; }; };
        options = {
          legend = { displayMode = "list"; placement = "bottom"; };
          tooltip = { mode = "multi"; sort = "none"; };
        };
      }
      {
        id = 6; type = "stat"; title = "RX Today";
        gridPos = { x = 18; y = 11; w = 6; h = 4; };
        targets = [ {
          datasource = { type = "prometheus"; uid = "prometheus"; };
          expr = ''sum(increase(node_network_receive_bytes_total{device!~"lo|veth.*"}[24h]))'';
          refId = "A";
        } ];
        fieldConfig = { defaults = { unit = "bytes"; }; };
      }
      {
        id = 7; type = "stat"; title = "TX Today";
        gridPos = { x = 18; y = 15; w = 6; h = 4; };
        targets = [ {
          datasource = { type = "prometheus"; uid = "prometheus"; };
          expr = ''sum(increase(node_network_transmit_bytes_total{device!~"lo|veth.*"}[24h]))'';
          refId = "A";
        } ];
        fieldConfig = { defaults = { unit = "bytes"; }; };
      }
      {
        id = 8; type = "row"; title = "Disk I/O"; collapsed = false;
        gridPos = { x = 0; y = 19; w = 24; h = 1; };
      }
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
        fieldConfig = { defaults = { unit = "Bps"; }; };
      }
      {
        id = 10; type = "row"; title = "System Health"; collapsed = false;
        gridPos = { x = 0; y = 28; w = 24; h = 1; };
      }
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
        };
      }
      {
        id = 12; type = "stat"; title = "Uptime";
        gridPos = { x = 18; y = 29; w = 3; h = 4; };
        targets = [ {
          datasource = { type = "prometheus"; uid = "prometheus"; };
          expr = "time() - node_boot_time_seconds";
          refId = "A";
        } ];
        fieldConfig = { defaults = { unit = "s"; }; };
      }
      {
        id = 13; type = "stat"; title = "Load (1m)";
        gridPos = { x = 21; y = 29; w = 3; h = 4; };
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
        scrape_interval = "5m";
        static_configs = [ { targets = [ "localhost:9100" ]; } ];
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
