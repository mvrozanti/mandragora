{ config, lib, pkgs, ... }:

let
  ytdlApp = pkgs.writers.writePython3Bin "ytdl-web" {
    flakeIgnore = [ "E501" "E265" "E302" "E305" "E402" "W605" ];
  } (builtins.readFile ../../snippets/ytdl-web.py);
in {
  mandragora.hub.services.ytdl-web = {
    port = 6685;
    userService = true;
    systemd = {
      description = "ytdl.mvr.ac — yt-dlp web frontend, drops mp3s into ~/Music";
      wantedBy = [ "default.target" ];
      after = [ "default.target" ];
      environment = {
        YTDL_HOST = "0.0.0.0";
        YTDL_PORT = "6685";
        YTDL_MUSIC_DIR = "/home/m/Music";
        YTDL_YT_DLP = "${pkgs.yt-dlp}/bin/yt-dlp";
        YTDL_FFMPEG_LOCATION = "${pkgs.ffmpeg}/bin";
      };
      path = [ pkgs.yt-dlp pkgs.ffmpeg pkgs.coreutils ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${ytdlApp}/bin/ytdl-web";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
