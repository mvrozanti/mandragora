{ config, pkgs, ... }:

let
  repository = "sftp:opc@mandragora-vps:/home/opc/backups/restic";
  passwordFile = "/persistent/backup/restic.pass";
  markerDir = "/persistent/backup";
  ageKeyFile = config.sops.age.keyFile;
  backupPaths = [ "/persistent/home/m/Documents" ];
  limitUploadKiB = "8192";
  excludeFile = ../../snippets/restic-excludes.txt;

  notifyBin = pkgs.writeShellScriptBin "telegram-notify" (
    builtins.readFile ../../../.local/bin/telegram-notify.sh
  );

  passgen = pkgs.writeShellApplication {
    name = "restic-passgen";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.openssl
    ];
    text = builtins.readFile ../../snippets/restic-passgen.sh;
  };

  resticBackup = pkgs.writeShellApplication {
    name = "restic-backup";
    runtimeInputs = [
      pkgs.restic
      pkgs.openssh
      pkgs.coreutils
    ];
    text = builtins.readFile ../../snippets/restic-backup.sh;
  };

  lifeboatVerify = pkgs.writeShellApplication {
    name = "restic-lifeboat-verify";
    runtimeInputs = [
      pkgs.restic
      pkgs.openssh
      pkgs.age
      pkgs.coreutils
    ];
    text = builtins.readFile ../../snippets/lifeboat-verify.sh;
  };

  backupAlert = pkgs.writeShellApplication {
    name = "backup-alert";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.libnotify
      notifyBin
    ];
    text = builtins.readFile ../../snippets/backup-alert.sh;
  };

  notifyEnv = "MANDRAGORA_NOTIFY_BIN=${notifyBin}/bin/telegram-notify";

  hardening = {
    Type = "oneshot";
    User = "m";
    Group = "users";
    WorkingDirectory = "/home/m";
    Nice = 15;
    IOSchedulingClass = "idle";
    OnFailure = "backup-failed@%n.service";
    EnvironmentFile = config.sops.secrets."llm_via_telegram/env".path;
  };
in
{
  systemd.tmpfiles.rules = [
    "d ${markerDir} 0700 m users - -"
  ];

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

  systemd.services.restic-backup = {
    description = "Daily resilient-tier restic backup of ~/Documents to the VPS";
    after = [
      "network-online.target"
      "tailscaled.service"
    ];
    wants = [
      "network-online.target"
      "tailscaled.service"
    ];
    serviceConfig = hardening // {
      TimeoutStartSec = "6h";
      Environment = [
        "HOME=/home/m"
        "RESTIC_REPOSITORY=${repository}"
        "RESTIC_PASSWORD_FILE=${passwordFile}"
        "RESTIC_EXCLUDE_FILE=${excludeFile}"
        "RESTIC_LIMIT_UPLOAD_KIB=${limitUploadKiB}"
        notifyEnv
        "BACKUP_PATHS=${builtins.concatStringsSep " " backupPaths}"
      ];
      ExecStartPre = "${passgen}/bin/restic-passgen";
      ExecStart = "${resticBackup}/bin/restic-backup";
    };
  };

  systemd.timers.restic-backup = {
    description = "Daily trigger for the resilient-tier restic backup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 03:30:00";
      Persistent = true;
      RandomizedDelaySec = "45m";
    };
  };

  systemd.services.restic-lifeboat = {
    description = "Weekly lifeboat verification: age key validity + restic repo integrity";
    after = [
      "network-online.target"
      "tailscaled.service"
    ];
    wants = [
      "network-online.target"
      "tailscaled.service"
    ];
    serviceConfig = hardening // {
      TimeoutStartSec = "2h";
      Environment = [
        "HOME=/home/m"
        "RESTIC_REPOSITORY=${repository}"
        "RESTIC_PASSWORD_FILE=${passwordFile}"
        "AGE_KEY_FILE=${ageKeyFile}"
        notifyEnv
      ];
      ExecStart = "${lifeboatVerify}/bin/restic-lifeboat-verify";
    };
  };

  systemd.timers.restic-lifeboat = {
    description = "Weekly trigger for lifeboat verification";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sat 06:00:00";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };
}
