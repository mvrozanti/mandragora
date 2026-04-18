{ config, pkgs, lib, ... }:

let
  # Use readFile on the source (not a derivation) to avoid Import-From-Derivation,
  # then substitute placeholders with replaceStrings at eval time.
  strayscli = pkgs.writeShellApplication {
    name = "strays";
    runtimeInputs = [ pkgs.findutils pkgs.util-linux ];
    text = builtins.replaceStrings
      [ "@VAULT@" "@USER_HOME@" ]
      [ "/persistent" "/home/m" ]
      (builtins.readFile ../../snippets/strays.sh);
  };

  # substituteAll maps Nix attribute names to @camelCase@ placeholders.
  healthCheckWatch = pkgs.substituteAll {
    src = ../../snippets/health-check.sh;
    diskWarnThreshold = "85";
    logFile = "/persistent/logs/strays/watch-$(date +%Y-%m-%d).log";
  };

  healthCheckDigest = pkgs.substituteAll {
    src = ../../snippets/health-check.sh;
    diskWarnThreshold = "75";
    logFile = "/persistent/logs/strays/digest-$(date +%Y-%m-%d).log";
  };

in
{
  environment.systemPackages = [ strayscli ];

  systemd.tmpfiles.rules = [
    "d /persistent/logs/strays 0755 root root -"
  ];

  systemd.services.audit-watch = {
    description = "Mandragora audit — watch (critical checks)";
    after = [ "local-fs.target" ];
    wants = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash ${healthCheckWatch}";
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  systemd.timers.audit-watch = {
    description = "Mandragora audit watch timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "30min";
      Persistent = true;
    };
  };

  systemd.services.audit-digest = {
    description = "Mandragora audit — daily digest (full report)";
    after = [ "local-fs.target" ];
    wants = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash ${healthCheckDigest}";
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  systemd.timers.audit-digest = {
    description = "Mandragora audit digest timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "10min";
      Persistent = true;
    };
  };
}
