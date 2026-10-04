{
  config,
  lib,
  pkgs,
  ...
}:

let
  systemDir = "/persistent/unit-health";
  telegramEnv = config.sops.secrets."llm_via_telegram/env".path;
  systemctl = config.systemd.package;

  withSystemDir =
    file: builtins.replaceStrings [ "@systemDir@" ] [ systemDir ] (builtins.readFile file);

  notifyBin = pkgs.writeShellScriptBin "telegram-notify" (
    builtins.readFile ../../../.local/bin/telegram-notify.sh
  );

  stamp = pkgs.writeShellApplication {
    name = "unit-health-stamp";
    bashOptions = [ "nounset" ];
    runtimeInputs = [
      pkgs.coreutils
      systemctl
    ];
    text = withSystemDir ../../../.local/bin/unit-health-stamp.sh;
  };

  notify = pkgs.writeShellApplication {
    name = "unit-health-notify";
    bashOptions = [
      "nounset"
      "pipefail"
    ];
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.curl
      pkgs.libnotify
      systemctl
      notifyBin
    ];
    text = withSystemDir ../../../.local/bin/unit-health-notify.sh;
  };

  report = pkgs.writers.writePython3Bin "unit-health-report" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ../../../.local/bin/unit-health-report.py);

  dropin = pkgs.replaceVars ../../snippets/unit-health-dropin.conf {
    stamp = "${stamp}/bin/unit-health-stamp";
  };
  self = ../../snippets/unit-health-self.conf;

  handlers = [
    "unit-health-failed@"
    "unit-health-recovered@"
  ];
  dropins = pkgs.linkFarm "unit-health-dropins" (
    lib.concatMap
      (
        scope:
        [
          {
            name = "lib/systemd/${scope}/service.d/50-unit-health.conf";
            path = dropin;
          }
        ]
        ++ map (h: {
          name = "lib/systemd/${scope}/${h}.service.d/90-unit-health-self.conf";
          path = self;
        }) handlers
      )
      [
        "system"
        "user"
      ]
    ++ [
      {
        name = "lib/systemd/user/mbsync-hotmail.service.d/90-unit-health-self.conf";
        path = self;
      }
    ]
  );

  handler = mode: {
    description = "Page on the ${mode} transition of %i";
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = telegramEnv;
      ExecStart = "${notify}/bin/unit-health-notify ${mode} %i";
    };
  };
  userHandler =
    mode:
    lib.recursiveUpdate (handler mode) {
      unitConfig.ConditionUser = "m";
    };
in
{
  environment.systemPackages = [ report ];

  systemd.packages = [ dropins ];

  systemd.tmpfiles.rules = [
    "d ${systemDir} 0755 root root -"
  ];

  systemd.services."unit-health-failed@" = handler "failed";
  systemd.services."unit-health-recovered@" = handler "recovered";
  systemd.user.services."unit-health-failed@" = userHandler "failed";
  systemd.user.services."unit-health-recovered@" = userHandler "recovered";

  systemd.user.services.unit-health-publish = {
    description = "Publish timer freshness for the watch.mvr.ac dead-man check";
    unitConfig.ConditionUser = "m";
    path = [
      pkgs.rsync
      pkgs.openssh
      systemctl
    ];
    environment.UNIT_HEALTH_SYSTEM_DIR = systemDir;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${report}/bin/unit-health-report";
      Nice = 19;
      TimeoutStartSec = "5min";
    };
  };

  systemd.user.timers.unit-health-publish = {
    description = "Publish timer freshness every 15 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "3min";
      OnUnitActiveSec = "15min";
    };
  };
}
