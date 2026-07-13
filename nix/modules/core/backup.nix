{ config, pkgs, ... }:

let
  ageKeyFile = config.sops.age.keyFile;
  backupUser = "m";
  remoteUser = "opc";
  vpsHost = "mandragora-vps";
  remoteDir = "/home/opc/backups/age-key";
  markerDir = "/persistent/backup";

  notifyBin = pkgs.writeShellScriptBin "telegram-notify" (
    builtins.readFile ../../../.local/bin/telegram-notify.sh
  );

  ageKeyBackup = pkgs.writeShellApplication {
    name = "age-key-backup";
    runtimeInputs = [
      pkgs.util-linux
      pkgs.openssh
      pkgs.age
      pkgs.coreutils
    ];
    text = builtins.readFile ../../snippets/age-key-backup.sh;
  };

  backupAlert = pkgs.writeShellApplication {
    name = "backup-alert";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.libnotify
      pkgs.curl
      notifyBin
    ];
    text = builtins.readFile ../../snippets/backup-alert.sh;
  };

  notifyEnv = "MANDRAGORA_NOTIFY_BIN=${notifyBin}/bin/telegram-notify";
in
{
  systemd.services."backup-failed@" = {
    description = "Alert + persistent marker when %i fails";
    serviceConfig = {
      Type = "oneshot";
      User = "m";
      Group = "users";
      EnvironmentFile = config.sops.secrets."llm_via_telegram/env".path;
      Environment = [
        "MANDRAGORA_BACKUP_MARKER_DIR=${markerDir}"
        notifyEnv
      ];
      ExecStart = "${backupAlert}/bin/backup-alert %i";
    };
  };

  systemd.services.age-key-backup = {
    description = "Weekly disaster-recovery mirror of the sops age key to the VPS";
    after = [
      "network-online.target"
      "tailscaled.service"
    ];
    wants = [
      "network-online.target"
      "tailscaled.service"
    ];
    unitConfig = {
      OnFailure = "backup-failed@%N.service";
    };
    serviceConfig = {
      Type = "oneshot";
      Nice = 15;
      IOSchedulingClass = "idle";
      TimeoutStartSec = "20m";
      EnvironmentFile = config.sops.secrets."llm_via_telegram/env".path;
      Environment = [
        "AGE_KEY_FILE=${ageKeyFile}"
        "BACKUP_USER=${backupUser}"
        "REMOTE_USER=${remoteUser}"
        "VPS_HOST=${vpsHost}"
        "REMOTE_DIR=${remoteDir}"
        notifyEnv
      ];
      ExecStart = "${ageKeyBackup}/bin/age-key-backup";
    };
  };

  systemd.timers.age-key-backup = {
    description = "Weekly trigger for the age-key disaster-recovery mirror";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sat 06:00:00";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };
}
