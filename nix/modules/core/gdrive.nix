{ config, lib, pkgs, ... }:

let
  cfg = config.mandragora.gdrive;
in
{
  options.mandragora.gdrive = {
    enable = lib.mkEnableOption "rclone-backed Google Drive mount under /mnt";

    remote = lib.mkOption {
      type = lib.types.str;
      default = "gdrive";
      description = "rclone remote name; must match the section header in the encrypted rclone.conf.";
    };

    mountPoint = lib.mkOption {
      type = lib.types.path;
      default = "/mnt/gdrive";
      description = "Filesystem path where Google Drive is mounted.";
    };

    cacheDir = lib.mkOption {
      type = lib.types.path;
      default = "/persistent/cache/rclone";
      description = "VFS cache directory; lives on the persistent subvolume so write-back uploads survive a reboot.";
    };

    uid = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "Owner uid presented for every file in the mount.";
    };

    gid = lib.mkOption {
      type = lib.types.int;
      default = 100;
      description = "Owner gid presented for every file in the mount.";
    };

    readOnly = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Mount Google Drive read-only.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.fuse.userAllowOther = true;

    sops.secrets."gdrive/rclone_conf" = {
      owner = "root";
      mode = "0400";
      restartUnits = [ "rclone-gdrive.service" ];
    };

    systemd.tmpfiles.rules = [
      "d /persistent/cache 0755 root root - -"
      "d ${cfg.cacheDir} 0700 root root - -"
      "d ${cfg.mountPoint} 0755 root root - -"
    ];

    systemd.services.rclone-gdrive = {
      description = "rclone mount: Google Drive at ${toString cfg.mountPoint}";
      after = [ "network-online.target" "run-secrets.d.mount" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "notify";
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${cfg.mountPoint}";
        ExecStart = lib.concatStringsSep " " ([
          "${pkgs.rclone}/bin/rclone mount"
          "${cfg.remote}: ${cfg.mountPoint}"
          "--config=${config.sops.secrets."gdrive/rclone_conf".path}"
          "--allow-other"
          "--uid=${toString cfg.uid}"
          "--gid=${toString cfg.gid}"
          "--umask=022"
          "--dir-cache-time=1000h"
          "--poll-interval=15s"
          "--vfs-cache-mode=full"
          "--vfs-cache-max-age=24h"
          "--cache-dir=${cfg.cacheDir}"
          "--log-level=INFO"
        ] ++ lib.optional cfg.readOnly "--read-only");
        ExecStop = "${pkgs.fuse3}/bin/fusermount3 -u ${cfg.mountPoint}";
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };
  };
}
