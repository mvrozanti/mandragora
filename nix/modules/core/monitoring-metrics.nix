{ pkgs, lib, ... }:

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
          static_configs = [ {
            targets = [ "localhost:9100" ];
            labels = { instance = "mandragora-desktop"; };
          } ];
        }
        {
          job_name = "node-vps";
          scrape_interval = "30s";
          static_configs = [ {
            targets = [ "100.84.78.83:9100" ];
            labels = { instance = "mandragora-vps"; };
          } ];
        }
        {
          job_name = "nvidia";
          scrape_interval = "1m";
          static_configs = [ {
            targets = [ "localhost:9835" ];
            labels = { instance = "mandragora-desktop"; };
          } ];
        }
        {
          job_name = "ebpf";
          scrape_interval = "15s";
          static_configs = [ {
            targets = [ "localhost:9435" ];
            labels = { instance = "mandragora-desktop"; };
          } ];
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

  environment.etc."alloy/journal.alloy".text = builtins.readFile ../../../.config/alloy/journal.alloy;
}
