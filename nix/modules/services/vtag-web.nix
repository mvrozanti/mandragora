{ config, lib, pkgs, ... }:

let
  cfg = config.mandragora.vtagWeb;
  vtagPkgs = pkgs.callPackage ../../pkgs/vtag-cli.nix {};
in
{
  options.mandragora.vtagWeb = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the vtag.mvr.ac runner web UI (port 8093, user service).";
    };
    targetDir = lib.mkOption {
      type = lib.types.path;
      description = ''
        Directory the vtag-server subprocess will recursively tag when
        the user clicks Start. Set per host; no default.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    mandragora.hub.services.vtag-web = {
      port = 8093;
      userService = true;
      systemd = {
        description = "vtag.mvr.ac — vtag runner web UI";
        wantedBy = [ "default.target" ];
        after = [ "default.target" ];
        environment = {
          VTAG_HUB_TARGET_DIR = toString cfg.targetDir;
          VTAG_HUB_LISTEN_PORT = "8093";
          VTAG_HUB_VTAG_BIN = "${vtagPkgs.vtag}/bin/vtag";
        };
        serviceConfig = {
          ExecStart = "${vtagPkgs.vtag-server}/bin/vtag-server";
          Restart = "always";
          RestartSec = "5s";
          ProtectHome = false;
          PrivateTmp = true;
          NoNewPrivileges = true;
          RestrictAddressFamilies = "AF_UNIX AF_INET AF_INET6";
          MemoryMax = "8G";
          OOMScoreAdjust = 200;
        };
      };
    };
  };
}
