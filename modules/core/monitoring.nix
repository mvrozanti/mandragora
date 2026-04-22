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
