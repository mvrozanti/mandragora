{ config, lib, pkgs, ... }:

let
  workdir = "/var/lib/mympd";
  cachedir = "/var/cache/mympd";
in {
  environment.systemPackages = [ pkgs.mympd ];

  users.users.mympd = {
    isSystemUser = true;
    group = "mympd";
    home = workdir;
    createHome = false;
    extraGroups = [ "mpd" ];
  };
  users.groups.mympd = {};

  systemd.tmpfiles.rules = [
    "d ${workdir}  0750 mympd mympd - -"
    "d ${cachedir} 0750 mympd mympd - -"
  ];

  mandragora.hub.services.mympd = {
    port = 6680;
    systemd = {
      description = "myMPD — modern MPD web client";
      after = [ "network.target" "tailscaled.service" "mpd.service" ];
      wants = [ "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        MYMPD_HTTP_HOST = "0.0.0.0";
        MYMPD_HTTP_PORT = "6680";
        MYMPD_SSL = "false";
        MYMPD_MPD_HOST = "127.0.0.1";
        MYMPD_MPD_PORT = "6600";
        MYMPD_LOGLEVEL = "5";
      };
      serviceConfig = {
        User = "mympd";
        Group = "mympd";
        ExecStart = "${pkgs.mympd}/bin/mympd -w ${workdir} -a ${cachedir}";
        Restart = "on-failure";
        RestartSec = "5s";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadWritePaths = [ workdir cachedir ];
      };
    };
  };
}
