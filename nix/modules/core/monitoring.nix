{ config, pkgs, lib, ... }:

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
          expr = "topk(10, abs(delta(dirsize_bytes[5m])))";
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
          expr = "topk(10, abs(delta(dir_inode_count[5m])))";
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
            expr = "nvidia_smi_utilization_gpu_ratio * 100";
            legendFormat = "GPU Core %";
            refId = "A";
          }
          {
            datasource = { type = "prometheus"; uid = "prometheus"; };
            expr = "nvidia_smi_utilization_memory_ratio * 100";
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
          expr = "nvidia_smi_temperature_gpu";
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

      # ── Row: Per-cgroup network ────────────────────────────────────────────
      {
        id = 20; type = "row"; title = "WAN traffic by cgroup (eBPF)"; collapsed = false;
        gridPos = { x = 0; y = 28; w = 24; h = 1; };
      }
      {
        id = 21; type = "timeseries"; title = "Top 10 cgroups — WAN TCP RX";
        gridPos = { x = 0; y = 29; w = 12; h = 9; };
        targets = [ {
          datasource = { type = "prometheus"; uid = "prometheus"; };
          expr = "topk(10, rate(ebpf_exporter_cgroup_wan_tcp_recv_bytes_total[5m]))";
          legendFormat = "{{cgroup}}";
          refId = "A";
        } ];
        fieldConfig = { defaults = { unit = "Bps"; custom = { fillOpacity = 20; }; }; };
        options = {
          legend = { displayMode = "list"; placement = "bottom"; };
          tooltip = { mode = "multi"; sort = "desc"; };
        };
      }
      {
        id = 22; type = "timeseries"; title = "Top 10 cgroups — WAN TCP TX";
        gridPos = { x = 12; y = 29; w = 12; h = 9; };
        targets = [ {
          datasource = { type = "prometheus"; uid = "prometheus"; };
          expr = "topk(10, rate(ebpf_exporter_cgroup_wan_tcp_send_bytes_total[5m]))";
          legendFormat = "{{cgroup}}";
          refId = "A";
        } ];
        fieldConfig = { defaults = { unit = "Bps"; custom = { fillOpacity = 20; }; }; };
        options = {
          legend = { displayMode = "list"; placement = "bottom"; };
          tooltip = { mode = "multi"; sort = "desc"; };
        };
      }

      # ── Row: Disk I/O ──────────────────────────────────────────────────────
      {
        id = 8; type = "row"; title = "Disk I/O"; collapsed = false;
        gridPos = { x = 0; y = 38; w = 24; h = 1; };
      }
      {
        id = 9; type = "timeseries"; title = "Disk I/O (nvme0n1)";
        gridPos = { x = 0; y = 39; w = 24; h = 8; };
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
        gridPos = { x = 0; y = 47; w = 24; h = 1; };
      }
      {
        id = 11; type = "timeseries"; title = "CPU & Memory";
        gridPos = { x = 0; y = 48; w = 18; h = 8; };
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
        gridPos = { x = 18; y = 48; w = 3; h = 8; };
        targets = [ {
          datasource = { type = "prometheus"; uid = "prometheus"; };
          expr = "time() - node_boot_time_seconds";
          refId = "A";
        } ];
        fieldConfig = { defaults = { unit = "s"; }; };
      }
      {
        id = 13; type = "stat"; title = "Load (1m)";
        gridPos = { x = 21; y = 48; w = 3; h = 8; };
        targets = [ {
          datasource = { type = "prometheus"; uid = "prometheus"; };
          expr = "node_load1";
          refId = "A";
        } ];
        fieldConfig = { defaults = { unit = "short"; }; };
      }

      # ── Row: CPU ──────────────────────────────────────────────────────────────
      {
        id = 18; type = "row"; title = "CPU"; collapsed = false;
        gridPos = { x = 0; y = 56; w = 24; h = 1; };
      }
      {
        id = 19; type = "timeseries"; title = "CPU Usage by Mode";
        gridPos = { x = 0; y = 57; w = 24; h = 9; };
        targets = [ {
          datasource = { type = "prometheus"; uid = "prometheus"; };
          expr = ''avg by (mode) (rate(node_cpu_seconds_total{mode!~"idle|guest|guest_nice"}[5m])) * 100'';
          legendFormat = "{{mode}}";
          refId = "A";
        } ];
        fieldConfig = {
          defaults = {
            unit = "percent";
            min = 0;
            max = 100;
            custom = {
              fillOpacity = 20;
              stacking = { group = "A"; mode = "normal"; };
            };
          };
        };
        options = {
          legend = { displayMode = "list"; placement = "bottom"; };
          tooltip = { mode = "multi"; sort = "desc"; };
        };
      }
    ];
  };

  dashboardDir = pkgs.writeTextDir "mandragora-system.json" (builtins.toJSON dashboard);
in

{
  services.victoriametrics = {
    enable = true;
    listenAddress = "0.0.0.0:8428";
    retentionPeriod = "90d";
    prometheusConfig = {
      scrape_configs = [
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
        {
          job_name = "ebpf";
          scrape_interval = "15s";
          static_configs = [ { targets = [ "localhost:9435" ]; } ];
        }
      ];
    };
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

  services.prometheus.exporters.ebpf = {
    enable = true;
    listenAddress = "0.0.0.0";
    names = [ "network-cgroup" ];
  };

  systemd.services.prometheus-ebpf-exporter.serviceConfig.ExecStart = lib.mkForce ''
    ${pkgs.prometheus-ebpf-exporter}/bin/ebpf_exporter \
      --config.dir=${pkgs.ebpf-network-config} \
      --config.names=network-cgroup \
      --web.listen-address 0.0.0.0:9435
  '';

  services.grafana = {
    enable = true;
    settings = {
      server = {
        protocol = "http";
        http_addr = "0.0.0.0";
        http_port = 3000;
      };
      analytics.reporting_enabled = false;
      security.secret_key = "$__file{${config.sops.secrets."grafana/secret_key".path}}";
      users.allow_sign_up = false;
      "auth" = {
        disable_login_form = true;
        disable_signout_menu = true;
      };
      "auth.basic".enabled = false;
      "auth.anonymous" = {
        enabled = true;
        org_role = "Admin";
        org_name = "Main Org.";
      };
    };
    provision = {
      enable = true;
      datasources.settings = {
        apiVersion = 1;
        deleteDatasources = [ { name = "Prometheus"; orgId = 1; } ];
        datasources = [
          {
            name = "VictoriaMetrics";
            type = "prometheus";
            url = "http://localhost:8428";
            isDefault = true;
            uid = "prometheus";
          }
          {
            name = "Loki";
            type = "loki";
            url = "http://100.84.78.83:3100";
            uid = "loki";
            jsonData = { maxLines = 5000; timeout = 60; };
          }
        ];
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
      Nice = 19;
      CPUSchedulingPolicy = "idle";
      IOSchedulingClass = "idle";
      Type = "oneshot";
      User = "root";
      UMask = "0022";
      ExecStart = "${pkgs.du-exporter}/bin/du-exporter";
    };
  };

  systemd.timers.du-exporter = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnUnitActiveSec = "2min";
      OnBootSec = "2min";
      Persistent = true;
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/prometheus-node-exporter-textfiles 0755 root root - -"
  ];

  services.alloy = {
    enable = true;
    extraFlags = [ "--server.http.listen-addr=127.0.0.1:12345" ];
  };

  environment.etc."alloy/journal.alloy".text = ''
    loki.relabel "journal" {
      forward_to = []
      rule {
        source_labels = ["__journal__systemd_unit"]
        target_label  = "unit"
      }
      rule {
        source_labels = ["__journal__hostname"]
        target_label  = "hostname"
      }
      rule {
        source_labels = ["__journal_priority_keyword"]
        target_label  = "priority"
      }
    }

    loki.source.journal "system" {
      max_age       = "12h"
      relabel_rules = loki.relabel.journal.rules
      forward_to    = [loki.write.vps.receiver]
      labels = {
        host = "mandragora-desktop",
        job  = "systemd-journal",
      }
    }

    loki.write "vps" {
      endpoint {
        url = "http://100.84.78.83:3100/loki/api/v1/push"
      }
    }
  '';
}
