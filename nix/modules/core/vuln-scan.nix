{ pkgs, ... }:

let
  cveScan = pkgs.writeShellApplication {
    name = "cve-scan";
    runtimeInputs = [
      pkgs.vulnix
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
  environment.systemPackages = [ cveScan vulnPublish ];

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
    description = "Mandragora CVE scan weekly timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
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
