{ config, lib, pkgs, ... }:

let
  cfg = config.mandragora.emotionWeb;
  emotionWebPkg = pkgs.callPackage ../../pkgs/emotion-web.nix {};
in
{
  options.mandragora.emotionWeb = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the music.mvr.ac emotion-tagging web UI (port 8094, user service).";
    };
  };

  config = lib.mkIf cfg.enable {
    mandragora.hub.services.emotion-web = {
      port = 8094;
      userService = true;
      systemd = {
        description = "music.mvr.ac — emotion-tagging web UI";
        wantedBy = [ "default.target" ];
        after = [ "default.target" ];
        environment = {
          EMOTION_WEB_LISTEN_HOST = "0.0.0.0";
          EMOTION_WEB_LISTEN_PORT = "8094";
          EMOTION_HOME = "/home/m/Music";
          EMOTION_NIX_SHELL = "/run/current-system/sw/bin/nix-shell";
          EMOTION_GPU_LOCK = "/run/current-system/sw/bin/gpu-lock";
        };
        serviceConfig = {
          ExecStart = "${emotionWebPkg}/bin/emotion-web";
          Restart = "on-failure";
          RestartSec = "5s";
          ProtectHome = false;
          PrivateTmp = false;
          NoNewPrivileges = true;
          RestrictAddressFamilies = "AF_UNIX AF_INET AF_INET6";
          MemoryMax = "512M";
          OOMScoreAdjust = 200;
        };
      };
    };
  };
}
