{ config, pkgs, lib, ... }:

let
  tailnet = builtins.fromJSON (builtins.readFile ../../snippets/tailnet.json);
  mkSystemDashboard = {
    title,
    uid,
    instance,
    nic,
    disk,
    withGpu ? false,
    withEbpf ? false,
    withDirsize ? false,
    withFsUsage ? false,
  }: let
    inst = ''instance="${instance}"'';
  in {
    inherit title uid;
    schemaVersion = 38;
    version = 1;
    refresh = "5m";
    time = { from = "now-24h"; to = "now"; };
    panels = (lib.optionals withDirsize [
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
          expr = ''topk(10, abs(delta(dirsize_bytes{${inst}}[5m])))'';
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
          expr = ''topk(10, abs(delta(dir_inode_count{${inst}}[5m])))'';
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
    ]) ++ (lib.optionals withGpu [
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
            expr = ''nvidia_smi_utilization_gpu_ratio{${inst}} * 100'';
            legendFormat = "GPU Core %";
            refId = "A";
          }
          {
            datasource = { type = "prometheus"; uid = "prometheus"; };
            expr = ''nvidia_smi_utilization_memory_ratio{${inst}} * 100'';
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
          expr = ''nvidia_smi_temperature_gpu{${inst}}'';
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
    ]) ++ [
      # ── Row: Network ───────────────────────────────────────────────────────
      {
        id = 4; type = "row"; title = "Network"; collapsed = false;
        gridPos = { x = 0; y = 19; w = 24; h = 1; };
      }
      {
        id = 5; type = "timeseries"; title = "Network Traffic (${nic})";
        gridPos = { x = 0; y = 20; w = 18; h = 8; };
        targets = [
          {
            datasource = { type = "prometheus"; uid = "prometheus"; };
            expr = ''rate(node_network_receive_bytes_total{${inst},device="${nic}"}[5m])'';
            legendFormat = "rx";
            refId = "A";
          }
          {
            datasource = { type = "prometheus"; uid = "prometheus"; };
            expr = ''rate(node_network_transmit_bytes_total{${inst},device="${nic}"}[5m])'';
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
          expr = ''sum(increase(node_network_receive_bytes_total{${inst},device="${nic}"}[24h]))'';
          refId = "A";
        } ];
        fieldConfig = { defaults = { unit = "bytes"; }; };
      }
      {
        id = 7; type = "stat"; title = "TX Today";
        gridPos = { x = 21; y = 20; w = 3; h = 8; };
        targets = [ {
          datasource = { type = "prometheus"; uid = "prometheus"; };
          expr = ''sum(increase(node_network_transmit_bytes_total{${inst},device="${nic}"}[24h]))'';
          refId = "A";
        } ];
        fieldConfig = { defaults = { unit = "bytes"; }; };
      }
    ] ++ (lib.optionals withEbpf [
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
          expr = ''topk(10, rate(ebpf_exporter_cgroup_wan_tcp_recv_bytes_total{${inst}}[5m]))'';
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
          expr = ''topk(10, rate(ebpf_exporter_cgroup_wan_tcp_send_bytes_total{${inst}}[5m]))'';
          legendFormat = "{{cgroup}}";
          refId = "A";
        } ];
        fieldConfig = { defaults = { unit = "Bps"; custom = { fillOpacity = 20; }; }; };
        options = {
          legend = { displayMode = "list"; placement = "bottom"; };
          tooltip = { mode = "multi"; sort = "desc"; };
        };
      }
    ]) ++ [
      # ── Row: Disk I/O ──────────────────────────────────────────────────────
      {
        id = 8; type = "row"; title = "Disk I/O"; collapsed = false;
        gridPos = { x = 0; y = 38; w = 24; h = 1; };
      }
      {
        id = 9; type = "timeseries"; title = "Disk I/O (${disk})";
        gridPos = { x = 0; y = 39; w = 24; h = 8; };
        targets = [
          {
            datasource = { type = "prometheus"; uid = "prometheus"; };
            expr = ''rate(node_disk_read_bytes_total{${inst},device="${disk}"}[5m])'';
            legendFormat = "read";
            refId = "A";
          }
          {
            datasource = { type = "prometheus"; uid = "prometheus"; };
            expr = ''rate(node_disk_written_bytes_total{${inst},device="${disk}"}[5m])'';
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
            expr = ''100 - (avg(rate(node_cpu_seconds_total{${inst},mode="idle"}[5m])) * 100)'';
            legendFormat = "CPU %";
            refId = "A";
          }
          {
            datasource = { type = "prometheus"; uid = "prometheus"; };
            expr = ''(1 - (node_memory_MemAvailable_bytes{${inst}} / node_memory_MemTotal_bytes{${inst}})) * 100'';
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
          expr = ''time() - node_boot_time_seconds{${inst}}'';
          refId = "A";
        } ];
        fieldConfig = { defaults = { unit = "s"; }; };
      }
      {
        id = 13; type = "stat"; title = "Load (1m)";
        gridPos = { x = 21; y = 48; w = 3; h = 8; };
        targets = [ {
          datasource = { type = "prometheus"; uid = "prometheus"; };
          expr = ''node_load1{${inst}}'';
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
          expr = ''avg by (mode) (rate(node_cpu_seconds_total{${inst},mode!~"idle|guest|guest_nice"}[5m])) * 100'';
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
    ] ++ (lib.optionals withFsUsage [
      # ── Row: Filesystem ────────────────────────────────────────────────────
      {
        id = 30; type = "row"; title = "Filesystem"; collapsed = false;
        gridPos = { x = 0; y = 66; w = 24; h = 1; };
      }
      {
        id = 31; type = "timeseries"; title = "Filesystem Used %";
        gridPos = { x = 0; y = 67; w = 18; h = 8; };
        targets = [ {
          datasource = { type = "prometheus"; uid = "prometheus"; };
          expr = ''100 * (1 - (node_filesystem_avail_bytes{${inst},fstype!~"tmpfs|overlay|squashfs"} / node_filesystem_size_bytes{${inst},fstype!~"tmpfs|overlay|squashfs"}))'';
          legendFormat = "{{mountpoint}}";
          refId = "A";
        } ];
        fieldConfig = {
          defaults = {
            unit = "percent";
            min = 0;
            max = 100;
            thresholds = {
              mode = "absolute";
              steps = [ { color = "green"; value = null; } { color = "orange"; value = 80; } { color = "red"; value = 95; } ];
            };
          };
        };
        options = { legend = { displayMode = "list"; placement = "bottom"; }; };
      }
      {
        id = 32; type = "stat"; title = "Root FS Free";
        gridPos = { x = 18; y = 67; w = 6; h = 8; };
        targets = [ {
          datasource = { type = "prometheus"; uid = "prometheus"; };
          expr = ''node_filesystem_avail_bytes{${inst},mountpoint="/"}'';
          refId = "A";
        } ];
        fieldConfig = {
          defaults = {
            unit = "bytes";
            thresholds = {
              mode = "absolute";
              steps = [ { color = "red"; value = null; } { color = "orange"; value = 5368709120; } { color = "green"; value = 21474836480; } ];
            };
          };
        };
        options = { textMode = "value"; colorMode = "value"; graphMode = "area"; };
      }
    ]);
  };

  dashboardDesktop = mkSystemDashboard {
    title = "Mandragora Desktop";
    uid = "mandragora-desktop";
    instance = "mandragora-desktop";
    nic = "enp8s0";
    disk = "nvme0n1";
    withGpu = true;
    withEbpf = true;
    withDirsize = true;
  };

  dashboardVps = mkSystemDashboard {
    title = "Mandragora VPS";
    uid = "mandragora-vps";
    instance = "mandragora-vps";
    nic = "enp0s6";
    disk = "sda";
    withGpu = false;
    withEbpf = true;
    withDirsize = true;
    withFsUsage = true;
  };

  dashboardDir = pkgs.linkFarm "mandragora-grafana-dashboards" [
    {
      name = "mandragora-desktop.json";
      path = pkgs.writeText "mandragora-desktop.json" (builtins.toJSON dashboardDesktop);
    }
    {
      name = "mandragora-vps.json";
      path = pkgs.writeText "mandragora-vps.json" (builtins.toJSON dashboardVps);
    }
  ];
in

{
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
            url = "http://${tailnet.vps.ip}:3100";
            uid = "loki";
            jsonData = { maxLines = 20000; timeout = 60; };
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
}
