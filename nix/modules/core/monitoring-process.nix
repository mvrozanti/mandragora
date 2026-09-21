{ pkgs, ... }:

let
  processNamesExporter = pkgs.writers.writePython3Bin "process-names-exporter" {
    flakeIgnore = [
      "E501"
      "E265"
      "E302"
      "E305"
      "E402"
      "W605"
    ];
  } (builtins.readFile ../../snippets/process-names-exporter.py);
in
{
  systemd.services.process-names-exporter = {
    description = "Per-program process metrics, grouped by a name a human recognises";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    environment = {
      PROCESS_NAMES_HOST = "127.0.0.1";
      PROCESS_NAMES_PORT = "9256";
    };
    serviceConfig = {
      ExecStart = "${processNamesExporter}/bin/process-names-exporter";
      Restart = "always";
      RestartSec = 5;
      User = "root";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      PrivateTmp = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
      ];
      MemoryMax = "256M";
      CPUQuota = "40%";
    };
  };
}
