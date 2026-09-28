{
  config,
  lib,
  pkgs,
  ...
}:

let
  firewall = config.networking.firewall;

  firewallSpec = pkgs.writeText "vuln-firewall.json" (
    builtins.toJSON {
      inherit (firewall) allowedTCPPorts allowedTCPPortRanges trustedInterfaces;
      interfaces = lib.mapAttrs (_: v: {
        inherit (v) allowedTCPPorts allowedTCPPortRanges;
      }) firewall.interfaces;
    }
  );

  vulnExposure = pkgs.writers.writePython3Bin "vuln-exposure" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ../../../.local/bin/vuln-exposure.py);

  cveScan = pkgs.writeShellApplication {
    name = "cve-scan";
    runtimeInputs = [
      pkgs.vulnix
      vulnPublish
      pkgs.libnotify
      pkgs.jq
      pkgs.gawk
      pkgs.coreutils
    ];
    text = builtins.readFile ../../../.local/bin/cve-scan.sh;
  };

  vulnPublish = pkgs.writeShellApplication {
    name = "vuln-publish";
    runtimeInputs = [
      pkgs.jq
      pkgs.rsync
      pkgs.openssh
      pkgs.coreutils
      pkgs.gnused
      pkgs.inetutils
    ];
    text = builtins.readFile ../../../.local/bin/vuln-publish.sh;
  };
in
{
  environment.systemPackages = [
    cveScan
    vulnPublish
  ];

  systemd.services.vuln-exposure = {
    description = "Map listening sockets to the Nix packages behind them for vuln.mvr.ac";
    path = [
      pkgs.iproute2
    ];
    environment = {
      VULN_FIREWALL = "${firewallSpec}";
      VULN_EXPOSURE_OUT = "/run/vuln-exposure/exposure.json";
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${vulnExposure}/bin/vuln-exposure";
      RuntimeDirectory = "vuln-exposure";
      RuntimeDirectoryMode = "0755";
      RuntimeDirectoryPreserve = true;
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      PrivateTmp = true;
      NoNewPrivileges = true;
      Nice = 19;
    };
  };

  systemd.timers.vuln-exposure = {
    description = "Hourly exposure map for vuln.mvr.ac";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "1h";
    };
  };

  systemd.user.services.cve-scan = {
    description = "Mandragora CVE scan against current system closure";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${cveScan}/bin/cve-scan";
      TimeoutStartSec = "30min";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
  };

  systemd.user.timers.cve-scan = {
    description = "Mandragora CVE scan daily timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "1h";
      Persistent = true;
    };
  };

  systemd.user.paths.cve-scan = {
    description = "Re-run the CVE scan when a new system generation appears";
    wantedBy = [ "default.target" ];
    pathConfig.PathModified = "/nix/var/nix/profiles";
  };
}
