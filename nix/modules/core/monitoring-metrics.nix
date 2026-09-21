{ pkgs, lib, ... }:

let
  tailnet = builtins.fromJSON (builtins.readFile ../../snippets/tailnet.json);
  hubServices =
    (builtins.fromJSON (builtins.readFile ../../hosts/mandragora-vps/compose/hub/static/services.json))
    .services;
  probeTargets = map (svc: "https://${svc.host}") hubServices;
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
          static_configs = [
            {
              targets = [ "localhost:9100" ];
              labels = {
                instance = "mandragora-desktop";
              };
            }
          ];
        }
        {
          job_name = "node-vps";
          scrape_interval = "30s";
          static_configs = [
            {
              targets = [ "${tailnet.vps.ip}:9100" ];
              labels = {
                instance = "mandragora-vps";
              };
            }
          ];
        }
        {
          job_name = "process";
          scrape_interval = "15s";
          static_configs = [
            {
              targets = [ "localhost:9256" ];
              labels = {
                instance = "mandragora-desktop";
              };
            }
          ];
        }
        {
          job_name = "nvidia";
          scrape_interval = "1m";
          static_configs = [
            {
              targets = [ "localhost:9835" ];
              labels = {
                instance = "mandragora-desktop";
              };
            }
          ];
        }
        {
          job_name = "kindle";
          scrape_interval = "5m";
          scrape_timeout = "1m";
          scheme = "https";
          metrics_path = "/metrics";
          static_configs = [
            {
              targets = [ "kindle.mvr.ac" ];
              labels = {
                instance = "mandragora-kindle";
              };
            }
          ];
        }
        {
          job_name = "blackbox-subdomains";
          scrape_interval = "60s";
          scrape_timeout = "15s";
          metrics_path = "/probe";
          params.module = [ "http_reachable" ];
          static_configs = [ { targets = probeTargets; } ];
          relabel_configs = [
            {
              source_labels = [ "__address__" ];
              target_label = "__param_target";
            }
            {
              source_labels = [ "__param_target" ];
              target_label = "instance";
            }
            {
              target_label = "__address__";
              replacement = "localhost:9115";
            }
          ];
        }
        {
          job_name = "ebpf";
          scrape_interval = "15s";
          static_configs = [
            {
              targets = [ "localhost:9435" ];
              labels = {
                instance = "mandragora-desktop";
              };
            }
          ];
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

  services.prometheus.exporters.blackbox = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9115;
    configFile = ../../../.config/blackbox/blackbox.yml;
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

  systemd.services.alloy.serviceConfig.MemoryMax = "2G";

  environment.etc."alloy/journal.alloy".text = builtins.readFile ../../../.config/alloy/journal.alloy;
}
