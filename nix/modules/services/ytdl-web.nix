{ pkgs, ... }:

let
  src = ../../../.local/share/ytdl-web;
  hubStatic = ../../hosts/mandragora-vps/compose/hub/static;
  staticDir = pkgs.linkFarm "ytdl-web-static" (
    map
      (name: {
        inherit name;
        path = src + "/static/${name}";
      })
      [
        "index.html"
        "ytdl.css"
        "ytdl.js"
      ]
    ++
      map
        (name: {
          inherit name;
          path = hubStatic + "/${name}";
        })
        [
          "theme.css"
          "theme.js"
          "components.css"
        ]
  );
  ytdlApp = pkgs.writers.writePython3Bin "ytdl-web" {
    flakeIgnore = [
      "E501"
      "E265"
      "E302"
      "E305"
      "E402"
      "W605"
    ];
  } (builtins.readFile (src + "/app.py"));
in
{
  mandragora.hub.services.ytdl-web = {
    port = 6685;
    userService = true;
    systemd = {
      description = "ytdl.mvr.ac — yt-dlp web frontend, mp3s into ~/Music, mp4s into ~/Videos, or straight to the device, with a persistent history";
      wantedBy = [ "default.target" ];
      after = [ "default.target" ];
      environment = {
        YTDL_HOST = "0.0.0.0";
        YTDL_PORT = "6685";
        YTDL_MUSIC_DIR = "/home/m/Music";
        YTDL_VIDEO_DIR = "/home/m/Videos";
        YTDL_STATIC_DIR = "${staticDir}";
        YTDL_YT_DLP = "${pkgs.yt-dlp}/bin/yt-dlp";
        YTDL_FFMPEG_LOCATION = "${pkgs.ffmpeg}/bin";
        YTDL_CLAUDE = "${pkgs.claude-code}/bin/claude";
        YTDL_TAG_MODEL = "haiku";
      };
      path = [
        pkgs.yt-dlp
        pkgs.ffmpeg
        pkgs.coreutils
        pkgs.claude-code
      ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${ytdlApp}/bin/ytdl-web";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
